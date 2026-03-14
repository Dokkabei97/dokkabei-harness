
# Session Title
_A short and distinctive 5-10 word descriptive title for the session. Super info dense, no filler_

Elasticsearch 7.8.1→9.1.2 Custom Korean Morphology Analyzer Upgrade

# Current State
_What is actively being worked on right now? Pending tasks not yet completed. Immediate next steps._

**Status**: 🔴 **ES DOCKER CONTAINER OOM KILLED (Exit Code 137)**

**Plan File**: `/Users/admin/.claude/plans/structured-napping-hippo.md`

**Current Error** (Docker container crash):
```
ERROR: Elasticsearch died while starting up, with exit code 137
```
- Exit code 137 = **OOM Killer** terminated the process
- Kernel forcefully killed ES due to memory limit exceeded

**Progress**:
- ✅ plugin-descriptor.properties version fix worked - Plugin now loads!
- ✅ Docker volume configuration issue resolved by user
- ✅ **FIXED**: Runtime `NoClassDefFoundError: org/yaml/snakeyaml/Yaml`
- ✅ Snakeyaml + commons-io now included in build/libs/
- ⚠️ Dictionary files missing - `dict/*.dict` not in plugin deployment (still pending)
- 🔴 **CURRENT**: Docker container running out of memory

**Root Cause Identified**:
- ES log shows: `-Xms512m, -Xmx512m` (only 512MB heap allocated)
- Docker container memory limit too low for ES 9.x + Kibana + plugin
- `.kibana_task_manager` index searches failing with `NoShardAvailableActionException` (ES unstable from memory pressure)

**Next Steps**:
1. Increase Docker memory allocation:
   ```yaml
   # docker-compose.yml
   services:
     es01:
       environment:
         - "ES_JAVA_OPTS=-Xms1g -Xmx1g"  # Minimum 1GB
       deploy:
         resources:
           limits:
             memory: 2g  # Container limit
   ```
2. After ES starts stably, address dictionary files issue
3. Provide dict/*.dict files from ES 7.8.1 installation

# Task specification
_What did the user ask to build? Any design decisions or other explanatory context_

**Objective**: Upgrade custom Korean morphological analyzer (형태소분석기) from Elasticsearch 7.8.1 to Elasticsearch 9.1.2
**Problem**: Plugin builds successfully but doesn't load in ES 9.x runtime

**Current Sub-task**: Debug dictionary null pointer - dictionary loading failing silently

**Completed Sub-tasks**:
- ✅ ES 9.x API package migration
- ✅ AccessController removal for JDK 21 (simple removal approach)
- ✅ Gradle 9.x compatibility
- ✅ Test code ES 9.x migration
- ✅ plugin-descriptor.properties version update (java.version=21, elasticsearch.version=9.1.2)
- ✅ Dependency packaging fix (snakeyaml, commons-io added to copyToDependencies task)
- ✅ Plugin loads successfully in ES 9.x
- ⚠️ Dictionary files missing - user needs to provide dict/*.dict files from original installation
- 🔴 Docker memory configuration needed - ES crashing with exit code 137 (OOM)

# Files and Functions
_What are the important files? In short, what do they contain and why are they relevant?_

**Build Configuration** (`build.gradle`):
- `group = "com.danawa.search"`, `version = "2.0.0"`
- Java 21 toolchain
- ES dependency: `org.elasticsearch:elasticsearch:9.1.2`
- Other deps: commons-io 1.3.2, log4j-core 2.11.1, json 2019+
- `options.failOnError = false` (suppressing compile errors currently)

**Key Plugin Classes** (all reviewed):
- `AnalysisProductNamePlugin.java` (74 lines) - Main plugin entry, implements `AnalysisPlugin, ActionPlugin`. Registers: `getTokenFilters()`, `getTokenizers()`, `getAnalyzers()`, `getRestHandlers()`. **Compatible with ES 9.x**.
- `ProductNameAnalyzerProvider.java` (52 lines) - Extends `AbstractIndexAnalyzerProvider<Analyzer>`. Uses `ContextStore` for dictionary caching. **Compatible**.
- `ProductNameTokenizerFactory.java` (42 lines) - Extends `AbstractTokenizerFactory`. **Compatible**.
- `ProductNameAnalysisFilterFactory.java` (40 lines) - Extends `AbstractTokenFilterFactory`. Constructor takes `(IndexSettings, Environment, String, Settings)`. **Compatible**.
- `ProductNameAnalysisAction.java` (1817 lines) - **MOST AFFECTED**. Extends `BaseRestHandler`. Key methods needing NodeClient fixes:
  - `prepareRequest(RestRequest, NodeClient)` - line 155
  - `testAction()`, `distribute()`, `analyzeTextAction()`, `analyzeMultiParamsAction()` - lines 237-423
  - `isOneWaySynonym()`, `analyzeTextDetail()`, `analyzeTextDetailWriteJSON()` - lines 428-832
  - `analyzeMultiParamsText()`, `compileDictionary()`, `infoDictionary()`, `findDictionary()` - lines 1084-1343
  - `restoreDictionary()`, `bulkIndex()`, `fastcatIndex()`, `search()`, `buildQuery()` - lines 1348-1613
  - `makeSearchKeyword()`, `getSynonymListAction()` - lines 1615-1762
  - Inner class `DictionarySource` extends `DictionaryRepository` implements `Iterator<CharSequence[]>` - uses `Client` interface (lines 1650-1724)
- `SearchUtil.java` (450 lines) - Utility class with heavy ES API usage:
  - `TimeValue` constants at lines 43-44
  - `searchData(NodeClient, String)` - line 50
  - `upsertData(NodeClient, String, Map)` - line 72 (uses `XContentType`)
  - `deleteAllData(NodeClient, String)` - line 91 (uses `Scroll`, `ClearScrollRequest`)
  - `count(Client, String, QueryBuilder)` - line 142
  - `search(Client, ...)` - line 156
  - Inner classes: `SearchResultIterator`, `ScrollSearchResultIterator` - use `Client`, `Scroll`, `TimeValue`

**Custom Lucene Token Attributes** (`org.apache.lucene.analysis.tokenattributes`):
- `ExtraTermAttribute.java` / `ExtraTermAttributeImpl.java`
- `SynonymAttribute.java` / `SynonymAttributeImpl.java`
- `TokenInfoAttribute.java` / `TokenInfoAttributeImpl.java`

**Korean Analysis Components** (`com.danawa.search.analysis.korean`):
- `KoreanWordExtractor.java`, `MorphUtil.java`, `PreResult.java`, `PosTagProbEntry.java`

**Dictionary Classes** (`com.danawa.search.analysis.dict`):
- `ProductNameDictionary.java` (768 lines) - **NEEDS FIX**: NodeClient import at line 11, `compileDictionary(NodeClient client, DictionaryRepository repo, String filter, boolean exportFile)` at line 359, inner class `DictionaryRepository` abstract class at lines 763-767
- `SynonymDictionary.java`, `CompoundDictionary.java`, `MapDictionary.java`, `SetDictionary.java`, `TagProbDictionary.java`, `CustomDictionary.java`, `SpaceDictionary.java`

**Migration Documentation**:
- `/Users/admin/project/analysis-product2/claudedocs/elasticsearch-9-migration-guide.md` (361 lines) - Comprehensive guide with AS-IS/TO-BE code examples, JavaDoc links, migration checklist

**Branch**: `feature/new` (main: `master`)

# Workflow
_What bash commands are usually run and in what order? How to interpret their output if not obvious?_

**Build**: `./gradlew build` - Compiles and packages the plugin
**Test**: `./gradlew --no-daemon test --tests -DLOG_LEVEL=TRACE -DSYSPROP_LAUNCH_FOR_BUILD=false <TestClass>.<testMethod>`
**Test System Properties**:
- `SYSPROP_LAUNCH_FOR_BUILD` - true/false
- `SYSPROP_TEST_DICTIONARY_SETTING` - defaults to "INTERNAL"
- `SYSPROP_TEST_DICTIONARY_LOAD_EXTRA` - extra dictionary loading
- `SYSPROP_SAMPLE_TEXT_PATH` - path to sample text
- `LOG_LEVEL` - DEBUG/TRACE

# Errors & Corrections
_Errors encountered and how they were fixed. What did the user correct? What approaches failed and should not be tried again?_

**ES 9.x API Changes & Applied Fixes**:

| Component | Old (ES 7.x) | New (ES 9.x) | File(s) |
|-----------|--------------|--------------|---------|
| Client Package | `org.elasticsearch.client.node.NodeClient` | `org.elasticsearch.client.internal.node.NodeClient` | All files |
| XContent Package | `org.elasticsearch.common.xcontent.*` | `org.elasticsearch.xcontent.*` | DanawaSearchQueryBuilder.java |
| DeprecationHandler | `LoggingDeprecationHandler.INSTANCE` | `DeprecationHandler.IGNORE_DEPRECATIONS` | DanawaSearchQueryBuilder.java |
| XContentParser.createParser | `createParser(registry, handler, String)` | `createParser(registry, handler, InputStream)` - wrap with `ByteArrayInputStream` | DanawaSearchQueryBuilder.java |
| Environment API | `env.configFile()` | `env.configDir()` | ProductNameDictionary.java |
| REST Response | `BytesRestResponse` | `RestResponse` + `new BytesArray(bytes)` | ProductNameAnalysisAction.java |
| Plugin Info | `PluginDescriptor` | `PluginRuntimeInfo` + `.descriptor().getClassname()` | ProductNameAnalysisAction.java |
| prepareIndex | `prepareIndex(index, "_doc")` | `prepareIndex(index)` - type removed in ES 8+ | FastcatMigrateIndexer, DanawaBulkTextIndexer |
| getRestHandlers | Old signature | Added `NamedWriteableRegistry`, `Predicate<NodeFeature>` params | AnalysisProductNamePlugin.java |

**RemoteNodeClient Major Refactor**:
- ES 9.x NodeClient constructor requires `ProjectResolver` (internal only)
- **Solution**: Removed NodeClient inheritance, made standalone HTTP client
- Methods now return `JSONObject` instead of `ActionFuture<SearchResponse>`
- Added `count(String index, MatchQueryBuilder query)` returning `long` directly

**DictionarySource Class Update**:
- Added `RemoteNodeClient remoteClient` field and constructor
- Modified `getSource()` to handle both local Client and RemoteNodeClient
- Remote search parses JSONObject response and builds result list manually
- `restore()` only works with local Client (logs warning for remote)

**JSONObject Constructor Ambiguity** (ResourceResolver.java:70):
```java
// Fix: Add explicit cast to resolve overload ambiguity
ret = new JSONObject((Map<?, ?>) yaml.loadAs(reader, Map.class));
```

**Remaining Warnings** (non-blocking):
- Unchecked/unsafe operations in ProductNameAnalysisFilter.java (generic-related, not security)

**Gradle 9.x Breaking Changes** (build.gradle):
| Line | Old (deprecated) | New (Gradle 9.x) |
|------|-----------------|------------------|
| 83 | `jar.archivePath` | `jar.archiveFile` |
| 74 | `"${buildDir}/libs"` | `layout.buildDirectory.dir("libs")` |
| 87 | `"${buildDir}/jars"` | `layout.buildDirectory.dir("jars")` |

**Test Code Fixes** (ALL COMPLETE):

**ProductNameAnalysisActionTest.java**:
- Import changes (lines 5-9, 22-28):
  - Added: `java.io.ByteArrayInputStream`, `java.nio.charset.StandardCharsets`
  - Changed: `org.elasticsearch.common.xcontent.*` → `org.elasticsearch.xcontent.*`
  - Changed: `LoggingDeprecationHandler.INSTANCE` → `DeprecationHandler.IGNORE_DEPRECATIONS`
- Method body changes:
  - Line 127, 144, 173: `createParser(String)` → `createParser(new ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8)))`
- **CRITICAL**: ES 9.x `createParser()` no longer accepts String - must wrap with ByteArrayInputStream

**ProductNameAnalysisFilterTest.java**:
- Line 412: `new JSONObject(yaml.loadAs(istream, Map.class))` → `new JSONObject((Map<?, ?>) yaml.loadAs(istream, Map.class))` (same fix as ResourceResolver.java)

**RESOLVED - Plugin Version Mismatch**:
- ✅ `plugin-descriptor.properties` updated: java.version=21, elasticsearch.version=9.1.2
- Plugin now loads successfully after version fix

**RESOLVED - Runtime ClassNotFoundException**:
- Error: `java.lang.NoClassDefFoundError: org/yaml/snakeyaml/Yaml`
- Stack: `ResourceResolver.readYmlConfig()` → `ProductNameDictionary.loadDictionary()` → `ProductNameTokenizerFactory.<init>`
- Cause: `copyToDependencies` task only included `"json-*", "slf4j-api*"` - missing snakeyaml
- Fix Applied: Added `"snakeyaml-*", "commons-io-*"` to include pattern (build.gradle line 67)
- Build verified successful, all JARs now in build/libs/

**CURRENT - Dictionary Files Missing**:
- Error: `NullPointerException: Cannot invoke "ProductNameDictionary.getDictionary(String, java.lang.Class)" because "dictionary" is null`
- Root cause: `product-name-dictionary.yml` references dict files that don't exist in plugin deployment
- **CRITICAL FINDING**: `src/main/resources/dict/` folder does NOT exist!
- Only partial dict files in test resources: `src/test/resources/dict/unit.dict`, `src/test/resources/dict/unit_synonym.dict`
- Dictionary config (`product-name-dictionary.yml`) lists 12 required dictionary files in `dict/` folder

**Required Dictionary Files** (from product-name-dictionary.yml):
```
dict/product.dict (type: SYSTEM)
dict/user.dict (type: SET)
dict/synonym.dict (type: SYNONYM)
dict/stop.dict (type: SET)
dict/space.dict (type: SPACE)
dict/compound.dict (type: COMPOUND)
dict/unit.dict (type: SET)
dict/unit_synonym.dict (type: SYNONYM_2WAY)
dict/maker.dict (type: CUSTOM)
dict/brand.dict (type: CUSTOM)
dict/category.dict (type: CUSTOM)
dict/english.dict (type: SET)
```

**Build Dependency Packaging** (VERIFIED):
```
build/libs/ (Plugin distribution)
├── analysis-product2-2.0.0.jar (235KB)
├── json-20190722.jar (65KB)
├── snakeyaml-2.2.jar (334KB) ✅
├── commons-io-1.3.2.jar (88KB) ✅
├── plugin-descriptor.properties
├── plugin-security.policy
└── product-name-dictionary.yml
❌ MISSING: dict/ folder with *.dict files
```

**ES 9.x Plugin Architecture Notes**:
- Classic plugins still supported - require matching `elasticsearch.version`
- ES validates version at load time, silently rejects mismatched plugins
- `plugin-security.policy` (ES 7.x) vs `entitlement-policy.yaml` (ES 9.x) - optional for classic plugins

# Codebase and System Documentation
_What are the important system components? How do they work/fit together?_

**Project Type**: Custom Elasticsearch morphological analyzer plugin for Korean product name analysis (상품명 형태소분석기)
**Package Structure**:
- `com.danawa.search.analysis.product` - Core product name analyzer, tokenizer, filters
- `com.danawa.search.analysis.korean` - Korean word extraction and morphology utilities
- `com.danawa.search.analysis.dict` - Dictionary management (synonyms, compounds, custom terms)
- `com.danawa.search.analysis.highlight` - Term highlighting
- `com.danawa.io` - Custom data I/O classes
- `com.danawa.util` - Utilities including `CharVector`, `ResourceResolver`, `ContextStore`
- `org.apache.lucene.analysis.tokenattributes` - Custom Lucene token attributes

**Technology Stack**:
- Elasticsearch 9.1.2 plugin architecture (upgrading from 7.8.1)
- Lucene (bundled with ES 9.x)
- Java 21
- Gradle build system
- Korean morphology dictionaries (`.txt` files)

**Plugin Architecture**:
- Entry point: `AnalysisProductNamePlugin.java`
- Analyzer: `ProductNameAnalyzer.java` via `ProductNameAnalyzerProvider.java`
- Tokenizer: `ProductNameTokenizer.java` via `ProductNameTokenizerFactory.java`
- Filter: `ProductNameAnalysisFilter.java` via `ProductNameAnalysisFilterFactory.java`
- REST Action: `ProductNameAnalysisAction.java`
- Rules: `rule/` package with `RuleOne` through `RuleFive`

# Learnings
_What has worked well? What has not? What to avoid? Do not duplicate items from other sections_

**What Worked Well**:
- Incremental compilation after each fix helped isolate issues
- TodoWrite tracking kept migration organized across sessions
- Previous session's migration guide served as accurate reference

**Key Technical Insights**:
- ES 9.x `XContentParser.createParser()` no longer accepts String directly - must use InputStream
- `PluginDescriptor` → `PluginRuntimeInfo` with chained `.descriptor().getClassname()` call
- `BytesRestResponse` actually **was** removed - use `RestResponse` + `BytesArray` instead
- RemoteNodeClient can't extend NodeClient in ES 9.x (constructor requires internal ProjectResolver)
- Document types (`_doc`) completely removed in ES 8+ - `prepareIndex(index)` only
- **JDK 21**: `AccessController.doPrivileged()` can be simply removed - ES 9.x Entitlements handles permissions

**What to Avoid**:
- Don't assume ES 7.x patterns work - check ES 9.x JavaDocs for every class
- `createParser(String)` overload doesn't exist - always use InputStream/byte[] approach
- Don't try to extend NodeClient for remote clients - use standalone HTTP implementation
- **JDK 21**: Don't use Entitlements policy file unless security hardening required - simple removal sufficient
- **Gradle 8.x**: `archivePath` property removed - use `archiveFile` instead
- **Gradle 8.x**: `buildDir` deprecated - use `layout.buildDirectory.dir()` for proper lazy evaluation
- **CRITICAL**: Always update `plugin-descriptor.properties` version fields when upgrading ES - ES **refuses to load** plugins with incorrect `elasticsearch.version` (silently in some cases)
- **Plugin descriptor location**: `src/main/resources/plugin-descriptor.properties` - gets copied to build output
- **Plugin ZIP packaging**: Only include plugin JAR + required external deps (like json JAR) + plugin-descriptor.properties
- **ES dependency**: Should be `compileOnly` not `implementation` - ES provides its own JARs at runtime
- **Build output observation**: If `build/jars/` contains elasticsearch-*.jar files, the dependency scope is wrong
- **ES 9.x security model**: Uses `entitlement-policy.yaml` instead of `plugin-security.policy`
- **module-info.java NOT required**: Classic plugins can be non-modular, using `ALL-UNNAMED` for entitlements
- **Silent rejection**: ES may silently refuse to load plugins without logging errors if version mismatches
- **Dependency packaging**: `copyToDependencies` task include pattern MUST list all required runtime deps (snakeyaml, commons-io, etc.) or they won't be in plugin distribution
- **Dictionary files separate from code**: Dict files (`*.dict`) are runtime data, not compiled into JAR - must be deployed alongside plugin
- **Dictionary loading paths**: Plugin searches `ResourceResolver.getResourceRoot()` first, then `env.configDir()` - dict files must exist in one of these locations
- **Docker Exit Code 137**: OOM Killer terminated ES - need to increase container memory
- **ES 9.x Memory Requirements**: Minimum 1GB heap (`-Xms1g -Xmx1g`), container needs 2GB+ total
- **Kibana task manager errors**: `NoShardAvailableActionException` on `.kibana_task_manager` index indicates ES memory pressure/instability

**AccessController Removal Pattern**:
The pattern is consistent across all 4 files - lambda body goes directly in method:
```java
// BEFORE:
SpecialPermission.check();
return AccessController.doPrivileged((PrivilegedAction<T>) () -> {
    // ... logic ...
    return result;
});

// AFTER:
// ... logic ...
return result;
```

**ES 9.x Migration Patterns**:
```java
// XContentParser
new ByteArrayInputStream(source.getBytes(StandardCharsets.UTF_8))

// REST Response
new RestResponse(RestStatus.OK, contentType, new BytesArray(bytes))

// Plugin Info
info.descriptor().getClassname()  // not info.getClassname()
```

# Key results
_If the user asked a specific output such as an answer to a question, a table, or other document, repeat the exact result here_

**Final Build Result** (ALL code compiles successfully):
```
./gradlew clean build -x test
BUILD SUCCESSFUL in 1s
5 actionable tasks: 5 executed
```
- Main code: ✅ Compiles with only unchecked operation warnings (non-blocking)
- Test code: ✅ Compiles successfully after ES 9.x xcontent migration
- Test execution: 22 tests completed, 5 failed (due to missing test resource files - FileNotFoundException/NullPointerException, NOT code issues)

**Summary of All Modified Files**:
| File | Changes |
|------|---------|
| SearchUtil.java | scroll → DEFAULT_SCROLL_KEEP_ALIVE, added count(RemoteNodeClient) overload |
| DanawaSearchQueryBuilder.java | xcontent imports, DeprecationHandler, createParser with ByteArrayInputStream |
| ProductNameDictionary.java | configFile() → configDir() |
| ResourceResolver.java | JSONObject cast `(Map<?, ?>)` |
| AnalysisProductNamePlugin.java | getRestHandlers signature with new params |
| ProductNameAnalysisAction.java | RestResponse+BytesArray, PluginRuntimeInfo, DictionarySource RemoteNodeClient support |
| FastcatMigrateIndexer.java | prepareIndex without type |
| DanawaBulkTextIndexer.java | prepareIndex without type, AccessController removed |
| FastcatMigrateIndexer.java | AccessController removed from run() |
| RemoteNodeClient.java | Complete refactor to standalone HTTP client |
| ProductNameAnalysisActionTest.java | xcontent imports, DeprecationHandler, ByteArrayInputStream wrapping |
| ProductNameAnalysisFilterTest.java | JSONObject cast `(Map<?, ?>)` |

# Worklog
_Step by step, what was attempted, done? Very terse summary for each step_

**Previous Sessions (Condensed)**:
1-28. ES 9.x API migration completed - all imports, method signatures, and patterns updated
29-62. AccessController removal (4 files) - JDK 21 compatibility
63-69. Gradle 9.x fixes (archivePath→archiveFile, buildDir→layout.buildDirectory)
70-84. Test code ES 9.x migration - xcontent imports, ByteArrayInputStream wrappers, JSONObject casts

**Plugin Loading Analysis (Ultrathink - 8 steps)**:
85-91. User reports plugin not loading in ES 9.x - `_cat/plugins` returns OK but empty
92-99. Analyzed plugin architecture - found `plugin-descriptor.properties` has wrong versions (7.8.1/Java 11)
100-107. WebFetch ES docs - confirmed classic plugins require exact version match; ES silently rejects mismatched plugins
108. Presented root cause analysis:
   - #1 CRITICAL: plugin-descriptor.properties version mismatch
   - #2 HIGH: ES dependency should be compileOnly
   - #3 MEDIUM: plugin-security.policy vs entitlement-policy.yaml

**This Session (Plugin Runtime Fix)**:
109. User fixed Docker volume issue - plugin now loads
110. New error: `NoClassDefFoundError: org/yaml/snakeyaml/Yaml` at runtime
111. Stack trace: `ResourceResolver.readYmlConfig()` → `ProductNameDictionary.loadDictionary()` → `ProductNameTokenizerFactory.<init>`
112. Root cause: `copyToDependencies` task only includes `"json-*", "slf4j-api*"` - missing snakeyaml
113. Fixed build.gradle line 67: Added `"snakeyaml-*", "commons-io-*"` to include pattern
114. Ran `./gradlew clean build -x test` - BUILD SUCCESSFUL
115. Verified build/libs/ now contains snakeyaml-2.2.jar and commons-io-1.3.2.jar
116. User redeployed plugin - ES starts successfully
117. New error on API call: `NullPointerException: dictionary is null`
118. Grep search for dictionary loading patterns in codebase - found `loadDictionary` calls in multiple files
119. Read ProductNameTokenizerFactory.java (42 lines) - dictionary loaded via ContextStore cache or `loadDictionary(env)` on miss
120. Read ProductNameDictionary.java:159-214 - dictionary loading logic revealed
121. Found config file search logic:
   - First tries: `ResourceResolver.getResourceRoot()` for plugin directory
   - Then tries: `env.configDir()` for ES config directory
   - Config file: `product-name-dictionary.yml`
122. Grep found `ANALYSIS_PROP = "product-name-dictionary.yml"` at line 63
123. Checked src/main/resources/ - config file exists there
124. Read product-name-dictionary.yml - found it references 12 dict files in `dict/` folder
125. **KEY FINDING**: `src/main/resources/dict/` folder does NOT exist! Dictionary files missing from project
126. Glob search confirmed only test resources have partial dict files (unit.dict, unit_synonym.dict)
127. Informed user: Must provide original dict/*.dict files from ES 7.8.1 installation and deploy to plugin directory

**Docker Memory Issue**:
128. User reported ES crash with exit code 137 during startup
129. Analyzed ES logs - found repeated `.kibana_task_manager` 503 errors with `NoShardAvailableActionException`
130. Identified memory configuration: `-Xms512m, -Xmx512m` (only 512MB heap)
131. Exit code 137 = Linux OOM Killer terminated the process
132. Recommended fix: Increase to `-Xms1g -Xmx1g` with 2GB container memory limit
