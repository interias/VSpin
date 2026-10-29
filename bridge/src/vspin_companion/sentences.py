"""Satzteilung für die Sprachausgabe (#79): Haikus Textstücke werden an Satzgrenzen geteilt, damit der erste Satz
schon gesprochen wird, während der Rest noch geschrieben wird."""

import re

# Satzende: . ! ? … (mit schließenden Anführungszeichen/Klammern), bestätigt erst durch das folgende Leerzeichen –
# am Ende des Puffers weiß man noch nicht, ob „3.“ oder „3.5“ kommt.
_BOUNDARY = re.compile(r"[.!?…]+[\"“”'’)\]]*(?=\s)")
_WORD_BEFORE = re.compile(r"(\w+)$")
# Ein-Satz-Grenze der harten Phasen (#78): schon hinter „142.“ ist Schluss – gröber als die Satzteilung oben.
_HARD_CUT = re.compile(r"(?<=[.!?…])\s+")
# Kürzel, nach denen ein Punkt kein Satzende ist („z. B.“, „ca.“); Zahlen mit Punkt („am 3. Mai“) ebenso.
ABBREVIATIONS = frozenset(
    {"z", "b", "d", "h", "u", "a", "o", "ca", "bzw", "usw", "etc", "evtl", "ggf", "vgl", "nr", "dr"}
)


class SentenceSplitter:
    """Nimmt Textstücke entgegen und gibt vollständige Sätze zurück; `flush` liefert den Rest am Ende."""

    def __init__(self) -> None:
        self._buffer = ""

    def feed(self, text: str) -> list[str]:
        self._buffer += text
        sentences: list[str] = []
        start = 0
        for match in _BOUNDARY.finditer(self._buffer):
            if match.group() == "." and _is_abbreviation(self._buffer[: match.start()]):
                continue
            sentence = self._buffer[start : match.end()].strip()
            if sentence:
                sentences.append(sentence)
            start = match.end()
        self._buffer = self._buffer[start:]
        return sentences

    def flush(self) -> list[str]:
        rest, self._buffer = self._buffer.strip(), ""
        return [rest] if rest else []


def split_sentences(text: str) -> list[str]:
    splitter = SentenceSplitter()
    return splitter.feed(text) + splitter.flush()


def first_sentence(text: str) -> str:
    """Nur der erste Satz im Sinne der Ein-Satz-Grenze (jedes Satzzeichen mit Leerraum dahinter beendet ihn)."""
    return _HARD_CUT.split(text, maxsplit=1)[0]


def _is_abbreviation(before: str) -> bool:
    word = _WORD_BEFORE.search(before)
    if word is None:
        return False
    token = word.group(1)
    return token.isdigit() or token.lower() in ABBREVIATIONS
