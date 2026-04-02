/**
 * Local Domain Manager
 * Handles creation and management of local domains like sirdavis99.pc
 * Uses /etc/hosts file manipulation and local DNS resolution
 */
import { existsSync, readFileSync } from 'fs';
import { homedir, platform } from 'os';
import { join } from 'path';
import { execSync } from 'child_process';
import type { UActionsConfig } from '../types';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export interface DomainEntry {
  subdomain: string;
  port: number;
  fullDomain: string;
  containerId?: string;
}

export class DomainManager {
  private config: UActionsConfig;
  private hostsFile: string;
  private domainEntries: Map<string, DomainEntry> = new Map();

  constructor(config: UActionsConfig) {
    this.config = config;
    this.hostsFile = platform() === 'win32' 
      ? 'C:\\Windows\\System32\\drivers\\etc\\hosts'
      : '/etc/hosts';
  }

  /**
   * Generate a base domain based on username and machine
   */
  static generateBaseDomain(): string {
    const username = homedir().split('/').pop() || 'user';
    const cleanUsername = username.toLowerCase().replace(/[^a-z0-9]/g, '');
    return `${cleanUsername}.pc`;
  }

  /**
   * Check if we're running on macOS
   */
  private isMacOS(): boolean {
    return platform() === 'darwin';
  }

  /**
   * Check if we're running on Linux
   */
  private isLinux(): boolean {
    return platform() === 'linux';
  }

  /**
   * Get the internal IP for local routing
   */
  private getInternalIP(): string {
    // Use 127.0.0.1 for localhost routing
    return '127.0.0.1';
  }

  /**
   * Read current hosts file
   */
  private readHostsFile(): string {
    try {
      if (existsSync(this.hostsFile)) {
        return readFileSync(this.hostsFile, 'utf-8');
      }
    } catch (error) {
      logger.warn(`Could not read hosts file: ${error}`);
    }
    return '';
  }

  /**
   * Check if we have permission to write to hosts file
   */
  async canWriteHostsFile(): Promise<boolean> {
    try {
      // On macOS/Linux, check if we can use sudo or if file is writable
      if (this.isMacOS() || this.isLinux()) {
        // Try to check if we can write (will fail without sudo)
        execSync(`test -w "${this.hostsFile}"`, { stdio: 'pipe' });
        return true;
      }
      return false;
    } catch {
      // Need sudo access
      return false;
    }
  }

  /**
   * Add a domain entry to /etc/hosts using sudo
   */
  async addDomain(subdomain: string, port: number, containerId?: string): Promise<boolean> {
    const fullDomain = `${subdomain}.${this.config.baseDomain}`;
    const ip = this.getInternalIP();
    
    const entry: DomainEntry = {
      subdomain,
      port,
      fullDomain,
      containerId,
    };

    this.domainEntries.set(subdomain, entry);

    // Build the hosts file entry
    // We'll use a marker to identify UActions entries
    const hostsEntry = `${ip} ${fullDomain} # uactions:${subdomain}`;

    try {
      const currentHosts = this.readHostsFile();
      
      // Check if entry already exists
      if (currentHosts.includes(fullDomain)) {
        // Update existing entry
        const lines = currentHosts.split('\n');
        const newLines = lines.map(line => {
          if (line.includes(fullDomain) && line.includes('# uactions:')) {
            return hostsEntry;
          }
          return line;
        });
        
        await this.writeHostsWithSudo(newLines.join('\n'));
      } else {
        // Add new entry
        const newContent = currentHosts.trim() + '\n' + hostsEntry + '\n';
        await this.writeHostsWithSudo(newContent);
      }

      // On macOS, also add to local DNS resolver if possible
      await this.setupLocalDNS(subdomain);

      logger.success(`Domain ${fullDomain} → localhost:${port}`);
      return true;
    } catch (error) {
      logger.error(`Failed to add domain ${fullDomain}: ${error}`);
      return false;
    }
  }

  /**
   * Remove a domain entry from /etc/hosts
   */
  async removeDomain(subdomain: string): Promise<boolean> {
    const fullDomain = `${subdomain}.${this.config.baseDomain}`;
    
    try {
      const currentHosts = this.readHostsFile();
      const lines = currentHosts.split('\n');
      const newLines = lines.filter(line => 
        !(line.includes(fullDomain) && line.includes('# uactions:'))
      );
      
      await this.writeHostsWithSudo(newLines.join('\n'));
      this.domainEntries.delete(subdomain);
      
      logger.success(`Removed domain ${fullDomain}`);
      return true;
    } catch (error) {
      logger.error(`Failed to remove domain ${fullDomain}: ${error}`);
      return false;
    }
  }

  /**
   * Write to hosts file using sudo
   */
  private async writeHostsWithSudo(content: string): Promise<void> {
    // Use tee with sudo to write to protected file
    const cmd = `echo '${content.replace(/'/g, "'\"'\"'")}' | sudo tee "${this.hostsFile}" > /dev/null`;
    execSync(cmd, { stdio: 'inherit' });
    
    // Flush DNS cache
    await this.flushDNSCache();
  }

  /**
   * Flush DNS cache on macOS
   */
  private async flushDNSCache(): Promise<void> {
    if (this.isMacOS()) {
      try {
        // macOS Ventura and later
        execSync('sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder', { stdio: 'pipe' });
        logger.debug('Flushed macOS DNS cache');
      } catch {
        // Ignore errors
      }
    }
  }

  /**
   * Setup local DNS resolver on macOS (optional enhancement)
   */
  private async setupLocalDNS(_subdomain: string): Promise<void> {
    if (!this.isMacOS()) return;

    // On macOS, we can also create resolver files for better DNS handling
    const resolverDir = '/etc/resolver';
    const resolverFile = join(resolverDir, this.config.baseDomain);
    
    try {
      // Check if resolver directory exists
      execSync(`test -d "${resolverDir}"`, { stdio: 'pipe' });
      
      // Create resolver entry pointing to localhost
      const resolverContent = `nameserver 127.0.0.1\nport 53\n`;
      const cmd = `echo '${resolverContent}' | sudo tee "${resolverFile}" > /dev/null`;
      execSync(cmd, { stdio: 'pipe' });
      
      logger.debug(`Created DNS resolver for ${this.config.baseDomain}`);
    } catch {
      // Resolver setup is optional, ignore errors
    }
  }

  /**
   * List all managed domains
   */
  listDomains(): DomainEntry[] {
    return Array.from(this.domainEntries.values());
  }

  /**
   * Get domain entry by subdomain
   */
  getDomain(subdomain: string): DomainEntry | undefined {
    return this.domainEntries.get(subdomain);
  }

  /**
   * Check if domain exists
   */
  hasDomain(subdomain: string): boolean {
    return this.domainEntries.has(subdomain);
  }

  /**
   * Cleanup all UActions entries from hosts file
   */
  async cleanup(): Promise<void> {
    try {
      const currentHosts = this.readHostsFile();
      const lines = currentHosts.split('\n');
      const newLines = lines.filter(line => !line.includes('# uactions:'));
      
      await this.writeHostsWithSudo(newLines.join('\n'));
      this.domainEntries.clear();
      
      logger.success('Cleaned up all UActions domain entries');
    } catch (error) {
      logger.error(`Failed to cleanup domains: ${error}`);
    }
  }

  /**
   * Validate base domain format
   */
  static validateBaseDomain(domain: string): boolean {
    // Allow patterns like: username.pc, my-domain.local, etc.
    const regex = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/i;
    return regex.test(domain);
  }
}
