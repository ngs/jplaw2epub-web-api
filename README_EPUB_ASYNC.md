# EPUB非同期生成機能

## 概要

大容量のEPUBファイル生成によるタイムアウトを回避するため、Cloud Run JobsとCloud Storageを使用した非同期処理を実装しました。

## アーキテクチャ

```
[Client] → [Cloud Run (GraphQL API)] → [Cloud Run Jobs API] → [Cloud Run Job]
                    ↓                                              ↓
              status check                                   EPUB generation
                    ↓                                              ↓
              [Cloud Storage] ←────────────────────────────────────┘
```

## セットアップ手順

### 1. Cloud Storageバケットの作成

Cloud Storageのセットアップは [jplaw2epub-generate-epub-job](https://github.com/ngs/jplaw2epub-generate-epub-job) リポジトリで行います。

### 2. Cloud Run Jobのデプロイ

別リポジトリ [jplaw2epub-generate-epub-job](https://github.com/ngs/jplaw2epub-generate-epub-job) をCloud Run Jobとしてデプロイしてください。

```bash
# リポジトリ内で実行
./deploy-job.sh
```

### 3. Cloud Runサービスの更新

GitHub Actionsで自動デプロイされるか、手動で以下を実行：

```bash
gcloud run services update jplaw2epub-api \
  --update-env-vars PROJECT_ID=YOUR_PROJECT_ID,EPUB_BUCKET_NAME=epub-storage,EPUB_JOB_NAME=epub-generator,REGION=asia-northeast1 \
  --region=asia-northeast1
```

## 使用方法

### GraphQL Query

```graphql
query GetEpub($id: String!) {
  epub(id: $id) {
    id
    status  # PENDING | PROCESSING | COMPLETED | FAILED
    signedUrl  # 生成完了時のダウンロードURL
    error  # エラー時のメッセージ
  }
}
```

### クライアント実装例

```javascript
async function downloadEpub(id) {
  const pollInterval = 3000; // 3秒
  const maxAttempts = 100; // 最大5分
  let attempts = 0;

  while (attempts < maxAttempts) {
    const { data } = await client.query({
      query: GET_EPUB_QUERY,
      variables: { id },
      fetchPolicy: 'network-only'
    });

    switch (data.epub.status) {
      case 'COMPLETED':
        window.location.href = data.epub.signedUrl;
        return;
      
      case 'FAILED':
        throw new Error(data.epub.error || 'EPUB生成に失敗しました');
      
      case 'PENDING':
      case 'PROCESSING':
        await new Promise(resolve => setTimeout(resolve, pollInterval));
        attempts++;
        break;
    }
  }
  
  throw new Error('タイムアウトしました');
}
```

## ファイル構造

```
Cloud Storage (epub-storage/)
├── v1.0.0/                           # アプリバージョン
│   ├── {id}.epub                    # 生成済みEPUB
│   └── {id}.status                  # 処理ステータス
```

## 環境変数

- `PROJECT_ID`: GCPプロジェクトID
- `EPUB_BUCKET_NAME`: Cloud Storageバケット名（デフォルト: epub-storage）
- `EPUB_JOB_NAME`: Cloud Run Job名（デフォルト: epub-generator）
- `REGION`: リージョン（デフォルト: asia-northeast1）

## コスト

月1000件のEPUB生成の場合（1ジョブあたり1分と仮定）：
- Cloud Run Jobs: 約$0.40（CPU: $0.32 + メモリ: $0.08）
- Cloud Storage: 約$0.07
- 合計: 約$0.47/月

## トラブルシューティング

### EPUBが生成されない

1. Cloud Run Jobの実行状況を確認：
```bash
gcloud run jobs executions list --job=epub-generator --region=asia-northeast1
```

2. 特定の実行のログを確認：
```bash
gcloud run jobs executions logs EXECUTION_ID --job=epub-generator --region=asia-northeast1
```

2. Cloud Storageバケットの権限確認：
```bash
gsutil iam get gs://epub-storage
```

### タイムアウトエラー

Cloud Run Jobのタイムアウト設定（現在1時間）を確認：
```bash
gcloud run jobs describe epub-generator --region=asia-northeast1
```