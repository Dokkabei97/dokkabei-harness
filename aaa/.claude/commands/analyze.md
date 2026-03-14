---
name: analyze
description: "Comprehensive code analysis with optional AI collaboration (Gemini/Copilot)"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /analyze - Code Analysis and Quality Assessment

## Triggers
- Code quality assessment requests for projects or specific components
- Security vulnerability scanning and compliance validation needs
- Performance bottleneck identification and optimization planning
- Architecture review and technical debt assessment requirements
- AI-assisted collaborative analysis with Gemini or Copilot

## Usage
```
/analyze [target] [options]

Options:
  --focus quality|security|performance|architecture  Analysis domain
  --depth quick|deep                                 Analysis depth
  --format text|json|report                          Output format
  --with copilot|gemini|codex                        AI collaboration mode
```

## Behavioral Flow

### Standard Analysis Flow
1. **Discover**: Categorize source files using language detection and project analysis
2. **Scan**: Apply domain-specific analysis techniques and pattern matching
3. **Evaluate**: Generate prioritized findings with severity ratings and impact assessment
4. **Recommend**: Create actionable recommendations with implementation guidance
5. **Report**: Present comprehensive analysis with metrics and improvement roadmap

### AI Collaboration Flow (--with option)
When `--with` option is specified, additional collaboration steps are executed:

1. **Prepare**: Build analysis prompt from target and options
2. **Execute AI Analysis**: Run external AI CLI tool
3. **Compare**: Compare Claude's analysis with AI response
4. **Synthesize**: Select optimal findings and recommendations
5. **Report**: Present unified analysis report with source attribution

## AI Collaboration Options

### --with gemini
Collaborates with Gemini CLI for analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json`
3. Display Gemini response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Analyze the following code for [focus area]: [target path]
Provide findings with severity ratings and actionable recommendations.
Focus on: [--focus value or 'comprehensive analysis']
Depth: [--depth value or 'deep']"
```

### --with copilot
Collaborates with Copilot CLI using multiple models for comprehensive analysis.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute 3 models sequentially:
   - `copilot --model gpt-5.2-codex -p "$PROMPT"`
   - `copilot --model claude-opus-4.5 -p "$PROMPT"`
   - `copilot --model gemini-3-pro-preview -p "$PROMPT"`
3. Display each model's response with Claude's commentary
4. Compare all results and identify consensus/divergence
5. Select optimal solution based on multi-model analysis
6. If copilot fails, retry execution

**Prompt Template:**
```bash
PROMPT="Perform code analysis on: [target path]
Analysis type: [--focus value or 'comprehensive']
Depth level: [--depth value or 'deep']
Provide:
- Severity-rated findings
- Actionable recommendations
- Code examples where applicable"
```

### --with codex
Collaborates with Codex CLI for analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `codex --model gpt-5.3-codex-spark xhigh exec "$PROMPT"`
3. Display Codex response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Perform code analysis on: [target path]
Analysis type: [--focus value or 'comprehensive']
Depth level: [--depth value or 'deep']
Provide:
- Severity-rated findings
- Actionable recommendations
- Code examples where applicable"
```

## Tool Coordination
- **Glob**: File discovery and project structure analysis
- **Grep**: Pattern analysis and code search operations
- **Read**: Source code inspection and configuration analysis
- **Bash**: External analysis tool execution (Gemini CLI, Copilot CLI)
- **Write**: Report generation and metrics documentation

## Key Patterns
- **Domain Analysis**: Quality/Security/Performance/Architecture specialized assessment
- **Pattern Recognition**: Language detection with appropriate analysis techniques
- **Severity Assessment**: Issue classification with prioritized recommendations
- **Report Generation**: Analysis results as structured documentation
- **AI Collaboration**: Multi-model comparison for enhanced accuracy

## Examples

### Comprehensive Project Analysis
```
/analyze
# Multi-domain analysis of entire project
# Generates comprehensive report with key findings and roadmap
```

### Focused Security Assessment
```
/analyze src/auth --focus security --depth deep
# Deep security analysis of authentication components
# Vulnerability assessment with detailed remediation guidance
```

### Performance Optimization Analysis
```
/analyze --focus performance --format report
# Performance bottleneck identification
# Generates report with optimization recommendations
```

### Quick Quality Check
```
/analyze src/components --focus quality --depth quick
# Rapid quality assessment of component directory
# Identifies code smells and maintainability issues
```

### AI-Assisted Analysis with Gemini
```
/analyze src --with gemini --focus security
# Security analysis with Gemini collaboration
# Compares Claude and Gemini findings for comprehensive coverage
```

### AI-Assisted Analysis with Copilot
```
/analyze --with copilot --depth deep
# Deep analysis with Copilot multi-model comparison
# Aggregates insights from GPT-5.1, Claude, and Gemini via Copilot
```

### AI-Assisted Analysis with Codex
```
/analyze src --with codex --focus performance
# Performance analysis with Codex collaboration
# Compares Claude and Codex findings for comprehensive coverage
```

### Combined Options
```
/analyze src/api --focus architecture --with gemini --format report
# Architecture review with Gemini collaboration
# Generates detailed report comparing both analyses
```

## Output Format

### Standard Output (--format text)
```
## Analysis Summary
- Target: [path]
- Focus: [domain]
- Depth: [level]
- Files Analyzed: [count]

## Findings
### Critical (X issues)
- [Finding description] - [File:Line]

### High (X issues)
...

## Recommendations
1. [Priority] [Recommendation]
   - Impact: [description]
   - Effort: [estimate]
```

### AI Collaboration Output
```
## Analysis Summary
[Standard summary]

## Claude Analysis
[Claude's findings and recommendations]

## [Gemini/Copilot] Analysis
[External AI findings]

## Comparison & Synthesis
- Consensus: [agreed findings]
- Divergence: [different perspectives]
- Selected Approach: [optimal recommendation with rationale]
```

## Boundaries

**Will:**
- Perform comprehensive static code analysis across multiple domains
- Generate severity-rated findings with actionable recommendations
- Execute AI collaboration via Gemini or Copilot CLI when requested
- Provide detailed reports with metrics and improvement guidance
- Compare and synthesize multi-source analysis results

**Will Not:**
- Execute dynamic analysis requiring code compilation or runtime
- Modify source code or apply fixes without explicit user consent
- Analyze external dependencies beyond import and usage patterns
- Use multiple `--with` options simultaneously (copilot/gemini/codex)
