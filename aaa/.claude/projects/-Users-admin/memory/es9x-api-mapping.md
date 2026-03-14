# ES 9.x Java API Client - API Mapping for DSearch

## ElasticsearchIndicesClient (client.indices())
- `analyze()` - 텍스트 분석
- `get()` - 인덱스 상세 조회 (GetIndexResponse)
- `getMapping()` / `putMapping()` - 매핑 CRUD
- `getSettings()` / `putSettings()` - 설정 CRUD
- `stats()` - 인덱스 통계
- `getAlias()` / `updateAliases()` / `putAlias()` - 앨리어스 관리
- `create()` / `delete()` / `exists()` - 인덱스 CRUD
- `getIndexTemplate()` / `putIndexTemplate()` / `deleteIndexTemplate()` - Composable Index Template
- `getTemplate()` / `putTemplate()` / `deleteTemplate()` - Legacy Template
- `simulateIndexTemplate()` / `simulateTemplate()` - 템플릿 시뮬레이션

## ElasticsearchIngestClient (client.ingest())
- `getPipeline()` / `putPipeline()` / `deletePipeline()` - 파이프라인 CRUD
- `simulate()` - 파이프라인 시뮬레이션

## GetAliasResponse
- `aliases()` returns `Map<String, IndexAliases>` (NOT `result()` or `keys()`)

## ElasticsearchClientFactory
- `getClient(clusterId)` - typed ElasticsearchClient
- `getLowLevelClient(clusterId)` - Rest5Client (ES proxy용)

## Key: 레거시 Low-Level Client → ES 9.x Typed Client 전환
- Pipeline: 레거시는 Low-Level REST Client 직접 사용 → ES 9.x는 IngestClient로 가능
- Template: 레거시는 `getTemplates` Low-Level → ES 9.x는 IndicesClient로 가능
- 유일하게 Low-Level 필요: ES Proxy (/elasticsearch/**)
