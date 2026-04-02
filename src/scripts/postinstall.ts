#!/usr/bin/env node
/**
 * Postinstall Script
 * Sets up the uactions folder structure after npm install
 */
import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const UACTIONS_DIR = join(homedir(), 'uactions');
const CONFIG_DIR = join(homedir(), '.uactions');

function setup() {
  console.log('Setting up UActions...');

  // Create uactions directory
  if (!existsSync(UACTIONS_DIR)) {
    mkdirSync(UACTIONS_DIR, { recursive: true });
    console.log(`Created: ${UACTIONS_DIR}`);
  }

  // Create config directory
  if (!existsSync(CONFIG_DIR)) {
    mkdirSync(CONFIG_DIR, { recursive: true });
    console.log(`Created: ${CONFIG_DIR}`);
  }

  // Create example artifact
  const exampleDir = join(UACTIONS_DIR, 'example-app');
  if (!existsSync(exampleDir)) {
    mkdirSync(exampleDir, { recursive: true });
    
    const exampleArtifact = {
      version: '1.0.0',
      name: 'Example App',
      source: {
        url: 'https://github.com/example/hello-world.git',
      },
      domain: {
        subdomain: 'hello',
      },
      container: {
        port: 8080,
      },
    };

    writeFileSync(
      join(exampleDir, 'artifact.json'),
      JSON.stringify(exampleArtifact, null, 2)
    );
    console.log(`Created example: ${exampleDir}/artifact.json`);
  }

  console.log('');
  console.log('╔═══════════════════════════════════════════════════════════╗');
  console.log('║                                                           ║');
  console.log('║   UActions installed successfully!                        ║');
  console.log('║                                                           ║');
  console.log('║   Run "uactions init" to get started                      ║');
  console.log('║                                                           ║');
  console.log('╚═══════════════════════════════════════════════════════════╝');
  console.log('');
}

setup();
