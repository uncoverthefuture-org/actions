import { generateContainerName, generateInternalPort, generateDomain, loadArtifact, validateArtifact } from '../utils/artifact';
import type { ArtifactConfig } from '../types';

describe('artifact utils', () => {
  const mockArtifact: ArtifactConfig = {
    version: '1.0.0' as const,
    name: 'Test App',
    source: {
      url: 'https://github.com/test/repo.git',
    },
    domain: {
      subdomain: 'testapp',
    },
    container: {
      port: 8080,
    },
  };

  describe('generateContainerName', () => {
    it('should generate container name from artifact with subdomain', () => {
      const name = generateContainerName(mockArtifact);
      expect(name).toBe('ua-test-app-testapp');
    });

    it('should handle artifacts with hyphens', () => {
      const artifact = { ...mockArtifact, name: 'my-test-app' };
      const name = generateContainerName(artifact);
      expect(name).toBe('ua-my-test-app-testapp');
    });
  });

  describe('generateInternalPort', () => {
    it('should generate a deterministic port based on name hash', () => {
      const port = generateInternalPort(mockArtifact);
      // Port should be between 10000-60000 based on hash
      expect(port).toBeGreaterThanOrEqual(10000);
      expect(port).toBeLessThan(60000);
    });

    it('should return same port for same artifact name', () => {
      const port1 = generateInternalPort(mockArtifact);
      const port2 = generateInternalPort(mockArtifact);
      expect(port1).toBe(port2);
    });
  });

  describe('generateDomain', () => {
    it('should generate full domain from subdomain and base', () => {
      const domain = generateDomain(mockArtifact, 'apple.pc');
      expect(domain).toBe('testapp.apple.pc');
    });
  });

  describe('loadArtifact', () => {
    it('should return error for non-existent file', () => {
      const result = loadArtifact('/non/existent/path.json');
      expect(result.success).toBe(false);
      expect(result.error).toContain('not found');
    });

    it('should return error for invalid JSON', () => {
      const result = loadArtifact(__filename); // Use this file as it exists but isn't JSON
      expect(result.success).toBe(false);
    });
  });

  describe('validateArtifact', () => {
    it('should validate a valid artifact', () => {
      const result = validateArtifact(mockArtifact);
      expect(result.success).toBe(true);
      expect(result.data).toBeDefined();
    });

    it('should reject artifact without name', () => {
      const result = validateArtifact({ source: { url: 'test' }, domain: { subdomain: 'test' } });
      expect(result.success).toBe(false);
      expect(result.error).toContain('name');
    });

    it('should reject artifact without source', () => {
      const result = validateArtifact({ name: 'test', domain: { subdomain: 'test' } });
      expect(result.success).toBe(false);
      expect(result.error).toContain('source');
    });

    it('should reject artifact without domain', () => {
      const result = validateArtifact({ name: 'test', source: { url: 'test' } });
      expect(result.success).toBe(false);
      expect(result.error).toContain('domain');
    });

    it('should reject invalid subdomain format', () => {
      const result = validateArtifact({
        name: 'test',
        source: { url: 'test' },
        domain: { subdomain: 'test_app' }
      });
      expect(result.success).toBe(false);
      expect(result.error).toContain('subdomain');
    });
  });
});
