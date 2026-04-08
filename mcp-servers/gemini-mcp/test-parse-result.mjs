import { parseResultOutput } from './src/gemini-exec.mjs';

const cases = [
  {
    name: 'case 1',
    raw: '',
    assert(result) {
      expect(result.status === 'failed', `expected failed status, got ${result.status}`);
      expect(/empty output/.test(result.error ?? ''), `expected empty output error, got ${result.error}`);
    }
  },
  {
    name: 'case 2',
    raw: '[gemini] Job not found: abc',
    assert(result) {
      expect(result.found === false, `expected found=false, got ${result.found}`);
    }
  },
  {
    name: 'case 3',
    raw: 'valid body content here',
    assert(result) {
      expect(result.available === true, `expected available=true, got ${result.available}`);
      expect(result.output === 'valid body content here', `unexpected output: ${result.output}`);
      expect(!('warnings' in result), `expected no warnings, got ${JSON.stringify(result.warnings)}`);
    }
  },
  {
    name: 'case 4',
    raw: 'body text\n\n_GaxiosError: Attempt 3 failed with status 429 MODEL_CAPACITY_EXHAUSTED',
    assert(result) {
      expect(result.available === true, `expected available=true, got ${result.available}`);
      expect(result.output === 'body text', `unexpected output: ${result.output}`);
      expect(result.warnings?.[0]?.type === 'trailing-error', `unexpected warnings: ${JSON.stringify(result.warnings)}`);
    }
  },
  {
    name: 'case 5',
    raw: '_GaxiosError at start',
    assert(result) {
      expect(result.available === false, `expected available=false, got ${result.available}`);
      expect(result.status === 'failed', `expected failed status, got ${result.status}`);
      expect(/upstream error before content/.test(result.error ?? ''), `unexpected error: ${result.error}`);
    }
  },
  {
    name: 'case 6',
    raw: 'Health Check OK',
    assert(result) {
      expect(result.available === false, `expected available=false, got ${result.available}`);
      expect(result.status === 'failed', `expected failed status, got ${result.status}`);
      expect(/placeholder/.test(result.error ?? ''), `unexpected error: ${result.error}`);
    }
  }
];

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

let passed = 0;

for (const testCase of cases) {
  const result = parseResultOutput(testCase.raw, 'job-test');
  testCase.assert(result);
  passed += 1;
  console.log(`${testCase.name}: pass`);
}

console.log(`all cases passed: ${passed}/${cases.length}`);
