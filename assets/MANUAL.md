# Instruction Manual: Mathematics KJV 1

This manual details the mathematical framework used to process the Authorized King James Version (AKJV) 1611 Pure Cambridge Edition.

## The Mathematics KJV 1 Logic

The core of this application is the transformation of natural language into a structured mathematical notation.

### 1. The "Of" Transformation
The connective "of" is treated as a function operator. In **Mathematics KJV 1** view, "of" is typically replaced by wrapping the succeeding object in parentheses.
- **Natural**: Word of God
- **Mathematical**: Word(God)

### 2. Continuity Mapping
Specific "Function Words" are mapped to unique symbols defined in `CONTINUITY.json`. This reduces linguistic redundancy and highlights the structural flow of the text. Symbols appear in **Red** to distinguish them from the base text.

### 3. Parentheses Logic
Complex phrases are nested using parentheses defined in `PARENTHESES.json`. This allows the reader to see the hierarchical relationship between different clauses and noun phrases within a verse.

## Advanced Search Functions

### Phrase Function: $Location \rightarrow Phrase$
A **Phrase Function** identifies the exact sequence of words associated with a specific mathematical coordinate.
- **Input**: `Gen1:1:1-5`
- **Logic**: Extracts the first through fifth words of Genesis 1:1.
- **Result**: `In the beginning God created`

### Inverse Relation: $Phrase \rightarrow \{Locations\}$
An **Inverse Relation** performs a search across the entire database to findทุก occurrence of a specific phrase, returning a set of all unique locations.
- **Input**: `holy mountain`
- **Result**: `{Exo15:17, Psa2:6, Psa3:4, ...}`

## Precision Indexing (Superscript)
To maintain mathematical integrity, every word in the AKJV 1611 PCE is assigned a fixed index. This index is immutable and serves as the primary key for all Phrase Functions. 

- **Italicized Words**: Words that were supplied by the translators (and appear in italics in standard editions) are tracked via the `isItalic` property and are styled accordingly in all views.
- **Punctuation**: Punctuation marks are treated as trailing metadata attached to the preceding word index, ensuring they do not interfere with phrase matching logic.
