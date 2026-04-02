/**
 * Init Command
 * Initializes UActions on the local machine
 */
import { Command } from 'commander';
import inquirer from 'inquirer';
import { DeploymentOrchestrator } from '../services/orchestrator';
import { DomainManager } from '../services/domain-manager';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export function createInitCommand(program: Command): void {
  program
    .command('init')
    .description('Initialize UActions on this machine')
    .option('-d, --domain <domain>', 'Set custom base domain (e.g., mydomain.pc)')
    .option('-e, --email <email>', 'Email for Let\'s Encrypt (enables HTTPS)')
    .option('--public', 'Enable public domain access with Let\'s Encrypt')
    .option('--skip-traefik', 'Skip automatic Traefik setup')
    .action(async (options) => {
      logger.banner('UActions Initialization');
      logger.info('Setting up your local deployment environment...\n');

      // Check if already initialized
      const orchestrator = new DeploymentOrchestrator();
      const status = orchestrator.getStatus();

      if (status.initialized) {
        const { proceed } = await inquirer.prompt([{
          type: 'confirm',
          name: 'proceed',
          message: `UActions is already initialized with domain ${status.baseDomain}. Reinitialize?`,
          default: false,
        }]);

        if (!proceed) {
          logger.info('Initialization cancelled');
          return;
        }
      }

      // Collect configuration
      let baseDomain = options.domain;
      let acmeEmail = options.email;
      let publicEnabled = options.public || false;

      if (!baseDomain) {
        const defaultDomain = DomainManager.generateBaseDomain();
        const { domain } = await inquirer.prompt([{
          type: 'input',
          name: 'domain',
          message: 'Choose your local domain:',
          default: defaultDomain,
          validate: (input: string) => {
            if (!DomainManager.validateBaseDomain(input)) {
              return 'Invalid domain format (e.g., username.pc)';
            }
            return true;
          },
        }]);
        baseDomain = domain;
      }

      if (!acmeEmail && publicEnabled) {
        const { email } = await inquirer.prompt([{
          type: 'input',
          name: 'email',
          message: 'Email for Let\'s Encrypt certificates:',
          validate: (input: string) => {
            if (!input || !input.includes('@')) {
              return 'Please enter a valid email address';
            }
            return true;
          },
        }]);
        acmeEmail = email;
      }

      // Show summary
      logger.section('Configuration Summary');
      logger.info(`Base Domain: ${baseDomain}`);
      logger.info(`Public HTTPS: ${publicEnabled ? 'Yes' : 'No (local HTTP only)'}`);
      if (acmeEmail) {
        logger.info(`ACME Email: ${acmeEmail}`);
      }
      logger.info(`Traefik Dashboard: Enabled`);

      const { confirm } = await inquirer.prompt([{
        type: 'confirm',
        name: 'confirm',
        message: 'Proceed with initialization?',
        default: true,
      }]);

      if (!confirm) {
        logger.info('Initialization cancelled');
        return;
      }

      try {
        await orchestrator.initialize({
          baseDomain,
          publicEnabled,
          acmeEmail,
        });

        logger.banner('Setup Complete!');
        logger.info('Next steps:');
        logger.info('1. Create a folder in ~/uactions/');
        logger.info('2. Add an artifact.json file');
        logger.info('3. Your app will be automatically deployed!');
        logger.info('');
        logger.info('Example:');
        logger.info('  mkdir ~/uactions/my-app');
        logger.info('  uactions create my-app --source https://github.com/user/repo.git');
      } catch (error) {
        logger.error(`Initialization failed: ${error}`);
        process.exit(1);
      }
    });
}
