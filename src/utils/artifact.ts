/**
 * Artifact configuration utilities
 */
import type { ArtifactConfig, ServiceResult } from '../types';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

/**
 * Default artifact values
 */
export const DEFAULT_ARTIFACT: Partial<ArtifactConfig> = {
  version: '1.0.0',
  container: {
    port: 8080,
    dockerfile: './Dockerfile',
    context: '.',
    memory: '512m',
    cpu: 0.5,
    restart: 'unless-stopped',
    healthCheck: '/',
  },
  build: {
    autoBuild: true,
    args: {},
  },
};

/**
 * Validate artifact configuration
 */
export function validateArtifact(config: unknown): ServiceResult<ArtifactConfig> {
  if (!config || typeof config !== 'object') {
    return { success: false, error: 'Artifact config must be an object' };
  }

  const artifact = config as Partial<ArtifactConfig>;

  // Required fields
  if (!artifact.name || typeof artifact.name !== 'string') {
    return { success: false, error: 'Artifact name is required and must be a string' };
  }

  if (!artifact.source || typeof artifact.source !== 'object') {
    return { success: false, error: 'Artifact source is required' };
  }

  if (!artifact.source.url || typeof artifact.source.url !== 'string') {
    return { success: false, error: 'Artifact source.url is required' };
  }

  if (!artifact.domain || typeof artifact.domain !== 'object') {
    return { success: false, error: 'Artifact domain is required' };
  }

  if (!artifact.domain.subdomain || typeof artifact.domain.subdomain !== 'string') {
    return { success: false, error: 'Artifact domain.subdomain is required' };
  }

  // Merge with defaults
  const merged: ArtifactConfig = {
    ...DEFAULT_ARTIFACT,
    ...artifact,
    container: {
      ...DEFAULT_ARTIFACT.container,
      ...artifact.container,
    },
    build: {
      ...DEFAULT_ARTIFACT.build,
      ...artifact.build,
    },
  } as ArtifactConfig;

  // Validate subdomain format
  const subdomainRegex = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/i;
  if (!subdomainRegex.test(merged.domain.subdomain)) {
    return { success: false, error: `Invalid subdomain format: ${merged.domain.subdomain}` };
  }

  return { success: true, data: merged };
}

/**
 * Load artifact from file
 */
export function loadArtifact(filePath: string): ServiceResult<ArtifactConfig> {
  try {
    if (!existsSync(filePath)) {
      return { success: false, error: `Artifact file not found: ${filePath}` };
    }

    const content = readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(content);
    return validateArtifact(parsed);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { success: false, error: `Failed to load artifact: ${message}` };
  }
}

/**
 * Check if a folder contains a valid artifact
 */
export function hasArtifact(folderPath: string): boolean {
  const artifactPath = join(folderPath, 'artifact.json');
  return existsSync(artifactPath);
}

/**
 * Generate container name from artifact
 */
export function generateContainerName(artifact: ArtifactConfig): string {
  const safeName = artifact.name.toLowerCase().replace(/[^a-z0-9]/g, '-');
  return `ua-${safeName}-${artifact.domain.subdomain}`;
}

/**
 * Generate full domain from artifact
 */
export function generateDomain(artifact: ArtifactConfig, baseDomain: string): string {
  return `${artifact.domain.subdomain}.${baseDomain}`;
}

/**
 * Generate internal port (for local routing)
 */
export function generateInternalPort(artifact: ArtifactConfig): number {
  // Generate a deterministic port based on name hash
  const hash = artifact.name.split('').reduce((acc, char) => {
    return ((acc << 5) - acc) + char.charCodeAt(0) | 0;
  }, 0);
  return 10000 + (Math.abs(hash) % 50000);
}
