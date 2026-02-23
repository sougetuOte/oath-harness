# agentsh コード解析レポート

**作成日**: 2026-02-23
**ソース**: https://github.com/canyonroad/agentsh (shallow clone)
**ローカル**: `vendor-src/agentsh/`
**規模**: 861 Go ファイル / 175K行

---

## 1. アーキテクチャ概要

### パッケージ構成

```
cmd/
  agentsh/              — メインCLIエントリポイント
  agentsh-shell-shim/   — /bin/sh 差し替え用シム
  agentsh-macwrap/      — macOS ESF+NE エンタープライズラッパー
  agentsh-unixwrap/     — Unix 汎用ラッパー
  agentsh-rlimit-exec/  — リソース制限付き実行
  pnacl-monitor/        — ネットワーク監視デーモン

internal/
  policy/               — ポリシーエンジン核心
    ancestry/           — プロセス祖先チェーン・汚染追跡
    identity/           — AIツールプロセス識別
    pattern/            — パターンマッチング（glob/regex/@class/literal）
  netmonitor/           — ネットワーク監視・制御
    ebpf/               — eBPFベースTCP接続フック
    pnacl/              — macOS pf + Linuxネットワーク
    unix/               — seccomp user-notify ベースUnixソケット制御
    redirect/           — DNS/TCP接続のリダイレクト相関
  api/                  — HTTPサーバ、FUSE統合、exec処理
  approval/             — ヒューマン・イン・ザ・ループ承認
  store/                — イベント永続化（JSONL/SQLite/OTEL/Webhook）
  llmproxy/             — LLM API透過プロキシ + DLP
  seccomp/              — seccomp-BPFフィルタ管理
  landlock/             — Linuxファイルシステム制限
  platform/             — OS固有実装（linux/darwin/windows/wsl2）
```

### データフロー

```
AIエージェントがコマンドを実行
  → agentsh exec $SID -- <command>
    → [HTTP API: api/exec.go]
      → policy.ContextEngine.CheckCommandWithContext()
          → TaintCache.IsTainted(pid)       # 汚染チェック
          → ProcessMatcher.Matches()         # AIエージェント特定
          → ChainRuleEvaluator.Evaluate()    # チェーンルール評価
          → evaluateContextPolicy()          # コンテキスト固有ポリシー
      → [ファイル操作] FUSE → policy.Engine.CheckFile()
      → [ネットワーク] DNSInterceptor / eBPF → policy.Engine.CheckNetworkCtx()
      → 決定: allow / deny / approve / redirect
        → store: SQLite/JSONL/OTEL イベント記録
        → approval: 必要時にヒューマン承認フロー
```

主要依存:
- `github.com/cilium/ebpf` — eBPFプログラム管理
- `github.com/seccomp/libseccomp-golang` — seccomp user-notify
- `github.com/hanwen/go-fuse/v2` — FUSE ファイルシステム
- `github.com/gobwas/glob` — 高速グロブマッチング
- `github.com/miekg/dns` — DNSプロトコル処理

---

## 2. ポリシーエンジンの実装詳細

### ポリシーモデル (`policy/model.go`)

```go
type Policy struct {
    FileRules            []FileRule
    NetworkRules         []NetworkRule
    CommandRules         []CommandRule
    UnixRules            []UnixSocketRule
    RegistryRules        []RegistryRule        // Windows レジストリ
    SignalRules          []SignalRule           // プロセス間シグナル
    DnsRedirectRules     []DnsRedirectRule
    ConnectRedirectRules []ConnectRedirectRule
    ProcessContexts      map[string]ProcessContext  // 親プロセス条件付きルール
    ProcessIdentities    map[string]ProcessIdentityConfig
}
```

決定値は **6種類**: `allow | deny | approve | redirect | audit | soft_delete`

### ルール定義の特徴

`CommandRule` には `Context` フィールドがあり、**実行深度による制御**が可能:

```go
type CommandRule struct {
    Commands     []string
    ArgsPatterns []string         // 引数の正規表現マッチ
    Decision     string
    RedirectTo   *CommandRedirect
    Context      ContextConfig    // direct/nested (depth 0/1+) の区別
    EnvAllow     []string         // コマンド固有の環境変数許可リスト
    EnvDeny      []string
    EnvBlockIteration *bool       // 環境変数の列挙を隠蔽
}
```

### 評価ロジック (`policy/engine.go`)

**"first match wins"** の線形スキャン + **デフォルト拒否**:

```go
func (e *Engine) CheckFile(p string, operation string) Decision {
    for _, r := range e.compiledFileRules {
        if !matchOp(r.ops, operation) { continue }
        for _, g := range r.globs {
            if g.Match(p) { return e.wrapDecision(r.rule.Decision, ...) }
        }
    }
    return e.wrapDecision("deny", "default-deny-files", "", nil)
}
```

コンパイル時にパスは `gobwas/glob`、ドメインは `.` 区切りグロブ、CIDR は `net.IPNet` に変換。

### 強制メカニズム（4層）

| 層 | 対象 | 技術 |
|:--|:--|:--|
| ファイル | 全ファイル操作 | FUSE |
| コマンド | execve | seccomp `SECCOMP_IOCTL_NOTIF_ADDFD` |
| ネットワーク | DNS + TCP | DNS プロキシ + eBPF cgroup-sockopt |
| Unix ソケット | connect/bind/listen/sendto | seccomp user-notify |

### approve モードの二段階動作

```go
case types.DecisionApprove:
    if e.enforceApprovals {
        // 完全強制: ユーザー承認が必要
        return Decision{..., Approval: &ApprovalInfo{Mode: ApprovalModeEnforced}}
    }
    // シャドウモード: 承認なしで実行、記録のみ
    return Decision{EffectiveDecision: types.DecisionAllow, ..., Mode: ApprovalModeShadow}
```

---

## 3. プロセス祖先チェーンの実装

### TaintCache — 汚染伝播の核心 (`ancestry/taint.go`)

```go
type ProcessTaint struct {
    SourcePID      int             // 最初のAIツールのPID
    SourceName     string          // "cursor", "claude-desktop" etc.
    ContextName    string          // 適用するポリシーコンテキスト名
    IsAgent        bool            // AIエージェントとして検出されたか
    Via            []string        // 中間プロセス名リスト
    ViaClasses     []ProcessClass  // 各中間プロセスの分類
    Depth          int             // ソースからのホップ数
    SourceSnapshot ProcessSnapshot // PID再利用検出用
}
```

`OnSpawn()` で親から子へ汚染伝播:

```go
func (c *TaintCache) OnSpawn(pid, ppid int, info *ProcessInfo) {
    if parentTaint, ok := c.taints[ppid]; ok {
        childTaint := &ProcessTaint{
            Via:   append(append([]string{}, parentTaint.Via...), info.Comm),
            Depth: parentTaint.Depth + 1,
        }
        c.taints[pid] = childTaint
    }
}
```

### プロセスクラスと「シェルランダリング」検出

`Classifier` がプロセスを6クラスに分類: Shell / Editor / Agent / BuildTool / LanguageServer / LanguageRuntime

**シェルランダリング検出**: 3重以上の連続シェルを検出
```go
analysis.ShellLaundering = maxConsecutiveShells >= 3
```

### PID再利用攻撃の防止 (`snapshot_linux.go`)

`/proc/PID/stat` の `starttime`（フィールド22）で照合:
```go
func parseStartTimeFromStat(stat string) (uint64, error) {
    fields := strings.Fields(stat[closeParenIdx+2:])
    return strconv.ParseUint(fields[19], 10, 64)
}
```

### ChainRuleEvaluator

複合論理（AND/OR/NOT）で以下の条件を組み合わせ:
- `ViaContains / ViaNotContains` — 中間プロセス名の有無
- `ConsecutiveClass` — 連続クラス回数（ランダリング検出）
- `IsTainted / IsAgent` — 汚染フラグ
- `DepthGT / DepthLT` — 深度条件
- `EnvContains / ArgsContain` — 実行時コンテキスト

---

## 4. ネットワーク制御の実装

### 3層制御アーキテクチャ

**層1: DNS プロキシ** (`netmonitor/dns.go`)
- UDPリスナーとして全DNS問い合わせを傍受
- `EvaluateDnsRedirect()` で偽の A レコードを合成して返却
- deny 時は REFUSED 応答
- 許可時のみアップストリームに転送

**層2: eBPF TCP接続フック** (`netmonitor/ebpf/`)
- CO-RE コンパイル済み eBPF オブジェクト (`connect_bpfel.o`) をカーネルにロード
- `cgroup/connect4` / `cgroup/connect6` で接続を hook
- リングバッファからカーネルイベント読み取り

```go
type ConnectEvent struct {
    PID, TGID uint32
    Dport     uint16
    Family    uint8     // AF_INET(2) or AF_INET6(10)
    DstIPv4   uint32
    DstIPv6   [16]byte
    Blocked   uint8
}
```

**層3: seccomp user-notify によるUnixソケット制御** (`netmonitor/unix/seccomp_linux.go`)
- `socket/connect/bind/listen/sendto` を傍受
- ユーザー空間で `ProcessVMReadv` によるソケットアドレス読み取り
- ポリシー評価後に `NotifRespond` で結果返却

**接続リダイレクト**: `tls_mode: rewrite_sni` で TLS ClientHello の SNI 書き換え対応。LLM APIエンドポイントの透過的切り替えが可能。

---

## 5. SELinux との類似点・相違点

| 特性 | SELinux | agentsh |
|:--|:--|:--|
| 実施レイヤー | LSM（カーネル内） | ユーザー空間（FUSE/seccomp/eBPF） |
| ポリシー記述 | 専用DSL | **YAML**（人間に優しい） |
| プロセス追跡 | MCS/MLS ラベル | **フル祖先チェーン + 分類** |
| 動的ポリシー | 制限的 | `ProcessContexts` で動的変化 |
| リダイレクト | なし | ファイル・コマンド・DNS・TCP |
| AI認識 | なし | **AIツールID + エージェント検出** |
| ヒューマン承認 | なし | `approve` 決定でHITL |
| クロスプラットフォーム | Linux専用 | **Linux/macOS/Windows** |

共通点: 強制アクセス制御、デフォルト拒否、型/クラスベース分類、コンテキスト伝播、ポリシー整合性検証（SHA256マニフェスト）

---

## 6. 信頼度・文脈による動的制御の有無

### 静的基盤

`Policy` は起動時に YAML から1回ロード（`sync.Once`）。以後変更しない。

### 動的要素（4つ）

**1. ProcessContext による実行時条件付きポリシー** (`context_eval.go`)
```
プロセスP がexecve呼び出し
  → TaintCache.IsTainted(P.pid) 確認
    → 汚染あり → ChainRuleEvaluator 実行
      → context policy を適用（denied/overrides/require_approval/allowed/default）
    → 汚染なし → 通常ポリシーへフォールバック
```

**2. エージェント検出の noisy-OR 信頼スコア** (`ancestry/detector.go`)

```go
// P(agent) = 1 - ∏(1 - P_i)
notAgent := 1.0
for _, signal := range result.Signals {
    notAgent *= (1 - SignalConfidence[signal])
}
result.Confidence = 1 - notAgent
```

シグナル信頼度: UserDeclared=1.0, SelfRegistered=1.0, EnvMarker=0.9, ArgPattern=0.9, ProcessPattern=0.8, Behavioral=0.6

**3. 行動分析** (`BehaviorDetector`)
- 直近1分間で10回超のexec → スコア+0.3
- LLM API アクセス → スコア+0.5

**4. `MarkAsAgent` による動的フラグ更新**
- ChainRule の `action: mark_as_agent` 発火 → `TaintCache.MarkAsAgent(pid)`
- 以後そのプロセスのポリシー評価が変化

**結論**: 「静的ポリシーファイル + 動的プロセスコンテキスト評価」のハイブリッド。プロセスの親子関係と行動観察に基づいてポリシー適用が実行時に変化する。ただし**信頼蓄積による段階的緩和は未実装**。

---

## 7. Theme B（Trust Engine）への示唆

### 借りられるもの

1. **TaintCache パターン**: PID→ProcessTaint の O(1) マップ + 親→子への汚染伝播。セッション来歴追跡に直接転用可能
2. **ChainCondition の複合論理**: AND/OR/NOT でコンテキスト条件を記述する言語。Trust Engine のポリシー記述に完成度が高い
3. **noisy-OR 信頼スコア**: `1 - ∏(1-P_i)` で複数シグナルを合成。数学的に健全で Earned Autonomy の信頼スコア計算に使える
4. **RacePolicy**: レースコンディション時の OnMissingParent/OnPIDMismatch/OnValidationError 各々に allow/deny/approve を設定。非決定論的環境への適応
5. **ProcessSnapshot**: `/proc/PID/stat` の starttime でPID再利用検出。信頼スコア改ざん防止に有用

### 足りないもの

1. **動的な信頼スコアの昇降**: `IsAgent` フラグは一方向（上げるだけ）。成功による向上+違反による低下の双方向が必要
2. **信頼スコアのセッション超え永続化**: TaintCache はメモリ内でTTL付き。過去セッション実績の DB 永続化が必要
3. **ポリシーの段階的緩和**: 全ルールが最初から適用。信頼閾値超過で特定操作を自動許可する仕組みがない
4. **人間とLLMの相互検証ループ**: approve は全て人間 or 全て自動の二択。LLM自己評価→必要時のみ人間確認がない

---

## 8. 注目すべきコードパターン

### コンパイル時パターン変換

```go
// NewEngine() で全YAMLパターンを事前コンパイル
for _, r := range p.FileRules {
    for _, pat := range r.Paths {
        g, _ := glob.Compile(pat, '/')  // 起動時に1回
        cr.globs = append(cr.globs, g)
    }
}
```

### 多段フォールバック パターンマッチング

`pattern.go` が `glob | re: | @class | literal` の4種類を統一インターフェースで処理。`ClassRegistry` が `@shell`、`@agent` を実行時に解決するレイジーバインディング。

### wrapDecision による決定の正規化

全 Check* メソッドが `wrapDecision()` を経由。approve→Shadow/Enforced、redirect→EffectiveDecision=Allow の変換が一箇所に集約。判断ロジックとポリシー適用ロジックの明確な分離。

### SHA256マニフェストによるポリシー完全性検証

```go
func verifyHash(path string, data []byte, manifestPath string) error {
    actual := sha256.Sum256(data)
    if expected != hex.EncodeToString(actual[:]) {
        return fmt.Errorf("policy hash mismatch: %s", base)
    }
}
```

CI/CD でポリシーの SHA256 を事前計算→実行時に改ざん検出。Trust Engine のポリシー署名検証に直接借用可能。

### RacePolicy の三値設計

レースコンディション（親プロセス不在/PIDミスマッチ/バリデーションエラー）各々に独立ポリシーを設定。セキュリティと可用性のトレードオフを細粒度で制御。
