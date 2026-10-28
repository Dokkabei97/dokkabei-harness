---
type: llm
focus: last_message
---

PASS if the reply explains that tokens produced at index time are fixed in the existing segments so changing the dictionary does not re-analyze already-indexed documents (and that _reload_search_analyzers only reloads updateable search-time filters such as synonyms, not the nori tokenizer dictionary), AND prescribes creating a new index with the updated dictionary, reindexing, and atomically swapping an alias.
FAIL if it claims close/open or _reload_search_analyzers alone is enough for existing documents, or never mentions reindexing.
