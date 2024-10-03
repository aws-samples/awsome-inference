import path from 'path';
import {
  SecretsManagerClient,
  CreateSecretCommand,
  UpdateSecretCommand,
  DescribeSecretCommand,
} from '@aws-sdk/client-secrets-manager';
import dotenv from 'dotenv';

// Load environment variables from .env file
dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

// Initialize a Secrets Manager client
const client = new SecretsManagerClient({ region: process.env.AWS_REGION });

// List of secrets to upload
const secrets = ['TWILIO_AUTH_TOKEN', 'NGC_API_KEY'] as const;

// type SecretName = (typeof secrets)[number];

async function createSecret(
  secretName: string,
  secretValue: string,
): Promise<void> {
  const command = new CreateSecretCommand({
    Name: secretName,
    Description: `Secret for ${secretName}`,
    SecretString: secretValue,
  });
  await client.send(command);
  console.log(`Secret ${secretName} created successfully`);
}

async function updateSecret(
  secretName: string,
  secretValue: string,
): Promise<void> {
  const command = new UpdateSecretCommand({
    SecretId: secretName,
    SecretString: secretValue,
  });
  await client.send(command);
  console.log(`Secret ${secretName} updated successfully`);
}

async function describeSecret(secretName: string): Promise<boolean> {
  try {
    const command = new DescribeSecretCommand({ SecretId: secretName });
    await client.send(command);
    return true;
  } catch (error) {
    if (error instanceof Error && error.name === 'ResourceNotFoundException') {
      return false;
    }
    throw error;
  }
}

async function createOrUpdateSecret(
  secretName: string,
  secretValue: string,
): Promise<void> {
  const secretExists = await describeSecret(secretName);
  if (secretExists) {
    console.log(`Secret ${secretName} exists. Updating...`);
    await updateSecret(secretName, secretValue);
  } else {
    console.log(`Secret ${secretName} does not exist. Creating...`);
    await createSecret(secretName, secretValue);
  }
}

async function uploadSecrets(): Promise<void> {
  // Check if AWS_REGION is set
  if (!process.env.AWS_REGION) {
    console.error('AWS_REGION is not set in the .env file');
    process.exit(1);
  }

  for (const secret of secrets) {
    const secretValue = process.env[secret];
    if (secretValue) {
      await createOrUpdateSecret(secret, secretValue);
    } else {
      console.log(`Warning: ${secret} not found in .env file`);
    }
  }
  console.log('Secret upload process completed');
}

uploadSecrets().catch((error) => {
  console.error('Error during secret upload:', error);
  process.exit(1);
});
