You are running S14 of a paper-generation pipeline.

Return only the final Markdown verification report. Do not narrate your process.

## Topic
__TOPIC__

## References
__REFERENCES__

## URL Audit
__URL_AUDIT__

## Task
Verify that the cited works appear to exist and are described consistently.

## Requirements
- use the URL audit as the first layer
- for each major citation, state whether the title/author/year combination appears valid
- flag broken URLs, ambiguous citations, or missing bibliographic fields
- classify each citation as verified, partial, or unverified

## Output Format
# S14 Citation Verification

## Citation Status
- citation:
  - url_status:
  - bibliographic_status:
  - verdict:
  - notes:

## Broken Or Ambiguous Entries
...

## Follow-Up Fixes
...
