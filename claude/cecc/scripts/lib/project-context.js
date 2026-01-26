/**
 * Project Context Detection
 * Detects project type (Node, Kotlin/JVM, Python) and associated tools
 *
 * Supports: Node.js, Kotlin/Java (Gradle/Maven), Python (Poetry/pip)
 */

const fs = require('fs');
const path = require('path');
const { commandExists, readFile, log } = require('./utils');

// Project type definitions
const PROJECT_TYPES = {
  NODE: {
    name: 'Node.js',
    indicators: ['package.json'],
    lockfiles: ['package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lockb'],
    formatter: 'prettier',
    linter: 'eslint',
    testRunner: 'vitest|jest|mocha',
    buildCmd: 'npm run build',
    devCmd: 'npm run dev',
    testCmd: 'npm test'
  },
  KOTLIN: {
    name: 'Kotlin/JVM',
    indicators: ['build.gradle.kts', 'build.gradle', 'settings.gradle.kts', 'settings.gradle'],
    lockfiles: ['gradle.lockfile'],
    formatter: 'ktlint',
    linter: 'detekt',
    testRunner: 'junit|kotest',
    buildCmd: './gradlew build',
    devCmd: './gradlew bootRun',
    testCmd: './gradlew test'
  },
  JAVA: {
    name: 'Java',
    indicators: ['pom.xml'],
    lockfiles: [],
    formatter: 'google-java-format|spotless',
    linter: 'checkstyle|spotbugs',
    testRunner: 'junit|testng',
    buildCmd: './mvnw package',
    devCmd: './mvnw spring-boot:run',
    testCmd: './mvnw test'
  },
  PYTHON: {
    name: 'Python',
    indicators: ['pyproject.toml', 'setup.py', 'requirements.txt'],
    lockfiles: ['poetry.lock', 'Pipfile.lock', 'requirements.txt'],
    formatter: 'ruff|black',
    linter: 'ruff|flake8|pylint',
    testRunner: 'pytest',
    buildCmd: 'poetry build',
    devCmd: 'uvicorn app.main:app --reload',
    testCmd: 'pytest'
  },
  RUST: {
    name: 'Rust',
    indicators: ['Cargo.toml'],
    lockfiles: ['Cargo.lock'],
    formatter: 'rustfmt',
    linter: 'clippy',
    testRunner: 'cargo test',
    buildCmd: 'cargo build',
    devCmd: 'cargo run',
    testCmd: 'cargo test'
  },
  GO: {
    name: 'Go',
    indicators: ['go.mod'],
    lockfiles: ['go.sum'],
    formatter: 'gofmt|goimports',
    linter: 'golangci-lint',
    testRunner: 'go test',
    buildCmd: 'go build',
    devCmd: 'go run .',
    testCmd: 'go test ./...'
  }
};

// Detection priority (check in order)
const DETECTION_PRIORITY = ['KOTLIN', 'JAVA', 'PYTHON', 'RUST', 'GO', 'NODE'];

/**
 * Check if a file exists in the project directory
 */
function fileExists(projectDir, filename) {
  return fs.existsSync(path.join(projectDir, filename));
}

/**
 * Detect project type from project directory
 * @param {string} projectDir - Project root directory
 * @returns {object} - { type, config, detected }
 */
function detectProjectType(projectDir = process.cwd()) {
  const detected = [];

  for (const typeName of DETECTION_PRIORITY) {
    const config = PROJECT_TYPES[typeName];
    const hasIndicator = config.indicators.some(f => fileExists(projectDir, f));

    if (hasIndicator) {
      detected.push({
        type: typeName,
        name: config.name,
        config
      });
    }
  }

  // Return first detected (highest priority) or null
  if (detected.length > 0) {
    return {
      primary: detected[0],
      all: detected,
      isMonorepo: detected.length > 1
    };
  }

  return {
    primary: null,
    all: [],
    isMonorepo: false
  };
}

/**
 * Detect Python package manager
 */
function detectPythonPackageManager(projectDir = process.cwd()) {
  if (fileExists(projectDir, 'poetry.lock') || fileExists(projectDir, 'pyproject.toml')) {
    const pyproject = readFile(path.join(projectDir, 'pyproject.toml'));
    if (pyproject && pyproject.includes('[tool.poetry]')) {
      return {
        name: 'poetry',
        installCmd: 'poetry install',
        runCmd: 'poetry run',
        addCmd: 'poetry add'
      };
    }
  }

  if (fileExists(projectDir, 'Pipfile')) {
    return {
      name: 'pipenv',
      installCmd: 'pipenv install',
      runCmd: 'pipenv run',
      addCmd: 'pipenv install'
    };
  }

  if (fileExists(projectDir, 'requirements.txt')) {
    return {
      name: 'pip',
      installCmd: 'pip install -r requirements.txt',
      runCmd: 'python',
      addCmd: 'pip install'
    };
  }

  return {
    name: 'pip',
    installCmd: 'pip install',
    runCmd: 'python',
    addCmd: 'pip install'
  };
}

/**
 * Detect Kotlin/Java build tool
 */
function detectJvmBuildTool(projectDir = process.cwd()) {
  // Check for Gradle (preferred)
  if (fileExists(projectDir, 'build.gradle.kts')) {
    return {
      name: 'gradle-kotlin-dsl',
      buildFile: 'build.gradle.kts',
      wrapper: fileExists(projectDir, 'gradlew'),
      buildCmd: fileExists(projectDir, 'gradlew') ? './gradlew' : 'gradle',
      runCmd: fileExists(projectDir, 'gradlew') ? './gradlew bootRun' : 'gradle bootRun'
    };
  }

  if (fileExists(projectDir, 'build.gradle')) {
    return {
      name: 'gradle-groovy-dsl',
      buildFile: 'build.gradle',
      wrapper: fileExists(projectDir, 'gradlew'),
      buildCmd: fileExists(projectDir, 'gradlew') ? './gradlew' : 'gradle',
      runCmd: fileExists(projectDir, 'gradlew') ? './gradlew bootRun' : 'gradle bootRun'
    };
  }

  // Check for Maven
  if (fileExists(projectDir, 'pom.xml')) {
    return {
      name: 'maven',
      buildFile: 'pom.xml',
      wrapper: fileExists(projectDir, 'mvnw'),
      buildCmd: fileExists(projectDir, 'mvnw') ? './mvnw' : 'mvn',
      runCmd: fileExists(projectDir, 'mvnw') ? './mvnw spring-boot:run' : 'mvn spring-boot:run'
    };
  }

  return null;
}

/**
 * Check if formatter is available
 */
function isFormatterAvailable(formatter, projectDir = process.cwd()) {
  switch (formatter) {
    case 'prettier':
      return fileExists(projectDir, 'node_modules/.bin/prettier') ||
             commandExists('prettier');
    case 'ktlint':
      // ktlint is usually run via Gradle
      return fileExists(projectDir, 'build.gradle.kts') ||
             fileExists(projectDir, 'build.gradle') ||
             commandExists('ktlint');
    case 'ruff':
      return commandExists('ruff');
    case 'black':
      return commandExists('black');
    case 'rustfmt':
      return commandExists('rustfmt');
    case 'gofmt':
      return commandExists('gofmt');
    default:
      return false;
  }
}

/**
 * Get project context summary
 */
function getProjectContext(projectDir = process.cwd()) {
  const detection = detectProjectType(projectDir);

  if (!detection.primary) {
    return {
      detected: false,
      message: 'No recognizable project type detected'
    };
  }

  const context = {
    detected: true,
    type: detection.primary.type,
    name: detection.primary.name,
    isMonorepo: detection.isMonorepo,
    tools: {}
  };

  // Add type-specific context
  switch (detection.primary.type) {
    case 'PYTHON':
      context.tools.packageManager = detectPythonPackageManager(projectDir);
      context.tools.formatter = isFormatterAvailable('ruff', projectDir) ? 'ruff' :
                                isFormatterAvailable('black', projectDir) ? 'black' : null;
      break;

    case 'KOTLIN':
    case 'JAVA':
      context.tools.buildTool = detectJvmBuildTool(projectDir);
      context.tools.formatter = isFormatterAvailable('ktlint', projectDir) ? 'ktlint' : null;
      break;

    case 'NODE':
      // Node package manager is handled by package-manager.js
      context.tools.formatter = isFormatterAvailable('prettier', projectDir) ? 'prettier' : null;
      break;

    case 'RUST':
      context.tools.formatter = isFormatterAvailable('rustfmt', projectDir) ? 'rustfmt' : null;
      break;

    case 'GO':
      context.tools.formatter = isFormatterAvailable('gofmt', projectDir) ? 'gofmt' : null;
      break;
  }

  return context;
}

/**
 * Get human-readable project summary for logging
 */
function getProjectSummary(projectDir = process.cwd()) {
  const context = getProjectContext(projectDir);

  if (!context.detected) {
    return context.message;
  }

  let summary = `${context.name} project`;

  if (context.isMonorepo) {
    summary += ' (monorepo)';
  }

  if (context.tools.buildTool) {
    summary += ` | Build: ${context.tools.buildTool.name}`;
  }

  if (context.tools.packageManager) {
    summary += ` | PM: ${context.tools.packageManager.name}`;
  }

  if (context.tools.formatter) {
    summary += ` | Formatter: ${context.tools.formatter}`;
  }

  return summary;
}

module.exports = {
  PROJECT_TYPES,
  DETECTION_PRIORITY,
  detectProjectType,
  detectPythonPackageManager,
  detectJvmBuildTool,
  isFormatterAvailable,
  getProjectContext,
  getProjectSummary
};
