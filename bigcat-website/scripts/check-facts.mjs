/** Lists business facts still marked TODO in src/data/business.ts. Exit 1 if any REQUIRED fact is missing. */
import { loadServer } from './lib.mjs';

const { outstandingFacts } = await loadServer();
const facts = outstandingFacts();
if (!facts.length) {
  console.log('✔ All business facts supplied.');
  process.exit(0);
}
for (const f of facts) console.log(`${f.required ? '✖ REQUIRED' : '• optional'}  ${f.key.padEnd(26)} ${f.note}`);
process.exit(facts.some((f) => f.required) ? 1 : 0);
