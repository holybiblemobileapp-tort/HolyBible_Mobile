# Instruction Manual

## Newfangledness in the Use of words in the Holy Bible
The word is his identity; the same yesterday, and today and forever. God not only historical, but also real time and in the infinitive. From the 1st use, 2nd use, ..., nth use of a word; he constantly recycles himself in the usage of a word.
The word is a placeholder for the things he wants to say. And he says what he wants to say exactly and concisely as he wants to say it. They are well-formed formulas used by the Holy Ghost, the Spirit of liberty, to give us access to every degree of freedom associated with the use of a word. Putting them in your own words is doing so at your own risk, the burden of the proof lies on you. Every man's word is his own burden.
The Bible is a vector space of well-formed formulas that defines itself. All what we provide as explanations is dung that comes from man; for as many as desire to make a fair show in the flesh.
Biblical translations are corollaries from God, he is the Original. The Original is always with us as we are created in the image of God;
God : man ↦ God(man) = image(God);
e.g.
God : Abraham ↦ God(Abraham),
God : Isaac ↦ God(Isaac),
God : Jacob ↦ God(Jacob).  The Hebrew and Greek Texts are also corollaries. In choosing a translation, as the Versification reveals, you choose your Frame of Reference from which you will observe the Original.
In the Use of words in the Holy Bible, location of a word in the Bible takes precedence over etymology. Before man began using words, God is. God is that Frame where every word is at rest; he speaks to put them in motion. With men a word might be archaic, but not with God. With God they are the jargon of the Word of God. The disciple whom the Lord loved was abreast with him.

## Mathematics KJV 1, KJV 2, KJV UNCONSTRAINT
This manual details the mathematical framework used to process the Authorized King James Version (AKJV) 1611 Pure Cambridge Edition.

### The Mathematics KJV Logic

The core of this application is the transformation of natural language into a structured mathematical notation.

#### 1. Versification 
The 4-Vector versification makes each word a function of its location in the Bible.
- BookChapter:Verse:Breadth for every word.
- In 4-Vector Height:Depth:Length:Breadth for every word.

**The 4-Vector Dimensions:**
able to comprehend with all saints what = the breadth, and length, and depth, and height;(Eph3:18:3-18)
- **Height ($H$):** The Book index (0 to 66).
- **Depth ($D$):** The Chapter index within the book.
- **Length ($L$):** The Verse index within the chapter.
- **Breadth ($B$):** The Word index (Index) within the verse.
These are the Generalized Coordinates of every word in the Holy Bible.

#### 2. Book Abbreviation Convention
- **First 3 Characters** in the name of the Books are used for its abbreviation.
- Books like **Philemon** and **Jude**, which share the same first 3 characters as **Philippians** and **Judges**, are distinguished as Books with **CHAPTER 0**.
- This convention also applies to other single-chapter books: **Obadiah**, **2John**, and **3John**.
- **Jude** is abbreviated as `Jud0` (Chapter 0) and is positioned in its correct order before Revelation.
- **Philemon** is abbreviated as `Phi0` (Chapter 0).

#### 3. The "Of" Transformation
The connective "of" is treated as a function operator. In **Mathematics KJV 1** view, "of" is typically replaced by wrapping the succeeding object in parentheses.
- **Natural**: Word of God
- **Mathematical**: Word(God)

#### 4. Continuity Mapping
Specific "Function Words" are mapped to unique symbols defined in `CONTINUITY.json`. This reduces linguistic redundancy and highlights the structural flow of the text. Symbols appear in **Red** to distinguish them from the base text.

#### 5. Radiant Rendering (Neon Glow)
To represent the "Light" inherent in the text, the Mathematics views utilize a **Triple-Layered Radiant Engine**:
- **Cyan/Blue Bloom**: Applied to the base text to represent the breadth of the mathematical field.
- **Red Radiance**: Applied to Continuity symbols to highlight the functional "Heat" or connection points.
- **Pulse Glow**: The active word (playing audio) increases in intensity to 40.0 blur density for precise tracking.

#### 6. Parentheses Logic
Complex phrases are nested using parentheses defined in `PARENTHESES.json`. This allows the reader to see the hierarchical relationship between different clauses and noun phrases within a verse.

### Advanced Search Functions

#### Phrase Function: $Location \rightarrow Phrase$
A **Phrase Function** identifies the exact sequence of words associated with a specific mathematical coordinate.
- **Input**: `Gen1:1:1-5`
- **Logic**: Extracts the first through fifth words of Genesis 1:1.
- **Result**: `In the beginning God created`

#### Inverse Relation: $Phrase \rightarrow \{Locations\}$
An **Inverse Relation** performs a search across the entire database to find every occurrence of a specific phrase, returning a set of all unique locations.
- **Input**: `holy mountain`
- **Result**: `{Isa11:9:10-11, Isa56:7:8-9, Isa57:13:37-38, ...}`

#### Search Filtering
Search Results may contain hundreds of records. A filter is provided to limit the output between a specific range: $k < x < l$.
*Note: Using smaller ranges (e.g., 1-10) results in smoother and faster App performance.*

### Precision Indexing (Superscript)
To maintain mathematical integrity, every word in the AKJV 1611 PCE is assigned a fixed index. This index is immutable and serves as the primary key for all Phrase Functions. 

- **Italicized Words**: Words that were supplied by the translators (and appear in italics in standard editions) are tracked via the `isItalic` property and are styled accordingly in all views.
- **Punctuation**: Punctuation marks are treated as trailing metadata attached to the preceding word index, ensuring they do not interfere with phrase matching logic.
