const { awscdk } = require('projen');
const { JobPermission } = require('projen/lib/github/workflows-model');
const { UpgradeDependenciesSchedule } = require('projen/lib/javascript');
const { NodePackageManager } = require('projen/lib/javascript');
const AUTOMATION_TOKEN = 'PROJEN_GITHUB_TOKEN';

const project = new awscdk.AwsCdkTypeScriptApp({
  cdkVersion: '2.118.0',
  license: 'MIT-0',
  author: 'Court Schuett',
  copyrightOwner: 'Amazon',
  appEntrypoint: 'nim-voice-bot.ts',
  jest: false,
  projenrcTs: true,
  depsUpgradeOptions: {
    ignoreProjen: false,
    workflowOptions: {
      labels: ['auto-approve', 'auto-merge'],
      schedule: UpgradeDependenciesSchedule.WEEKLY,
    },
  },
  autoApproveOptions: {
    secret: 'GITHUB_TOKEN',
    allowedUsernames: ['schuettc'],
  },
  autoApproveUpgrades: true,
  packageManager: NodePackageManager.YARN_CLASSIC,
  projenUpgradeSecret: 'PROJEN_GITHUB_TOKEN',
  defaultReleaseBranch: 'main',
  name: 'nim-voice-bot',
  deps: [
    'dotenv',
    '@types/aws-lambda',
    '@aws-sdk/client-secrets-manager',
    '@aws-sdk/client-auto-scaling',
    '@aws-sdk/client-elastic-load-balancing-v2',
  ],
});

project.addTask('launch', {
  exec: 'yarn cdk deploy --require-approval never',
});

project.addTask('upload-secrets', {
  exec: 'ts-node scripts/uploadSecrets.ts',
});

project.tsconfigDev.file.addOverride('include', [
  'src/**/*.ts',
  './.projenrc.ts',
  'scripts/*.ts',
]);

project.eslint.addOverride({
  files: ['src/resources/**/*.ts'],
  rules: {
    'indent': 'off',
    '@typescript-eslint/indent': 'off',
  },
});

project.eslint.addOverride({
  files: ['./*.ts', './**/*.ts'],
  rules: {
    '@typescript-eslint/no-require-imports': 'off',
    'import/no-extraneous-dependencies': 'off',
    'import/no-unresolved': 'off',
  },
});

const common_exclude = [
  'docker-compose.yaml',
  'cdk.out',
  'cdk.context.json',
  'yarn-error.log',
  'dependabot.yml',
  '.DS_Store',
  '.env',
  '**/dist/**',
  '**/bin/**',
  '**/lib/**',
  'config.json',
];

project.gitignore.exclude(...common_exclude);
project.synth();
