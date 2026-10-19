"""Where a document is cut."""

import chunking


class TestLongUnits:
    """A unit the sentence pattern cannot split must still be cut."""

    def test_a_run_with_no_sentence_ends_is_cut_to_the_target(self):
        words = ("lorem ipsum dolor " * 300).strip()  # ~5,400 chars, no full stop
        chunks = chunking.split(words)
        assert len(chunks) >= 5
        assert all(len(c.text) <= chunking.TARGET for c in chunks)
        # Cut between words, never inside one.
        assert all(
            not c.text.startswith(" ") and "ipsum dolor lorem" in c.text for c in chunks[:-1]
        )

    def test_hindi_prose_is_cut_too(self):
        # `_SENTENCE` wants a Latin capital after a full stop; Devanagari has
        # neither, so this paragraph used to arrive as one unit of any length.
        text = ("यह किराये का समझौता दो साल के लिए है और जमा राशि वापस की जाएगी। " * 60).strip()
        chunks = chunking.split(text)
        assert len(chunks) >= 3
        assert all(len(c.text) <= chunking.TARGET for c in chunks)
        assert all(c.text for c in chunks)

    def test_ordinary_sentences_still_split_at_sentence_ends(self):
        sentence = "The deposit is returned within thirty days of moving out. "
        text = (sentence * 60).strip()  # ~3,500 chars of real sentences
        chunks = chunking.split(text)
        assert len(chunks) >= 3
        assert all(c.text.endswith(".") for c in chunks)
        assert all(len(c.text) <= chunking.TARGET for c in chunks)

    def test_indexes_are_consecutive_and_offsets_climb(self):
        chunks = chunking.split(("word " * 900).strip())
        assert [c.index for c in chunks] == list(range(len(chunks)))
        starts = [c.start for c in chunks]
        assert starts == sorted(starts)
