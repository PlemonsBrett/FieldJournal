"""Extract verified quest descriptions from this client's volatile WDB cache.

The beta's quest query payload has a binary prefix followed by a concatenated
title, objective summary, and description. Only known title/objective pairs are
accepted; unexpected records are skipped rather than guessing boundaries.
"""

from pathlib import Path
import re
import struct
import sys


QUESTS = {
    92517: ("The Criminal Element", "in the Shen'dar Highlands."),
    92550: ("Havoc in the Highlands", "take the head of Commander Cyclas."),
    93165: ("Mercy Falls on Deaf Ears", "or Gustberry Lowlands."),
    94488: ("The Ties That Bind", "in the Shadowgale Forest."),
    93951: ("A Little Beauty", "in the Shen'dar Highlands."),
    93319: ("Pilfered Windstones", "in the Shen'dar Highlands."),
    93036: ("Infiltrating the Cult", "in Shen'dar Village."),
    92551: ("Stolen Supplies", "in the Shen'dar Highlands."),
    93926: ("The Western Watch", "at the western watchtower."),
    96101: ("The Great Outdoors", "the Boosted Rest buff."),
    97967: ("Camping 101: Fishing", "proficiency in your skill."),
    93318: ("WANTED: Vulgara the Insatiable", "to Danarii Bellowveil."),
    92553: ("Restocking the Larders", "throughout the Shen'dar Highlands."),
    92528: ("Among the Faithful", "in the Shen'dar Highlands."),
    94411: ("Meddlesome Mages", "in Shen'dar Highlands."),
    92529: ("Falaath Village", "to regain the effect."),
    92516: ("Hippogryph Harrassment", "in the Shen'dar Highlands."),
}


def records(data):
    if data[:4] != b"TSQW":
        raise ValueError("Not a questcache.wdb file")
    offset = 24
    while offset + 8 <= len(data):
        quest_id, size = struct.unpack_from("<II", data, offset)
        offset += 8
        if quest_id == 0 and size == 0:
            break
        if size > 100_000 or offset + size > len(data):
            raise ValueError("Invalid quest record length")
        yield quest_id, data[offset : offset + size]
        offset += size


def extract(quest_id, payload):
    title, objective_end = QUESTS[quest_id]
    printable = re.findall(rb"[\x20-\x7e\r\n]{100,}", payload)
    if not printable:
        raise ValueError("No long text block")
    block = printable[-1].decode("utf-8").lstrip()
    if not block.startswith(title):
        raise ValueError("Title did not match record")
    body = block[len(title) :]
    end = body.find(objective_end)
    if end < 0:
        raise ValueError("Objective ending did not match record")
    description = body[end + len(objective_end) :].strip().replace("\r\n", "\n")
    if len(description) < 40:
        raise ValueError("Description too short")
    return description


def lua_long_string(value):
    for equals in ("", "=", "=="):
        if "]" + equals + "]" not in value:
            return "[" + equals + "[" + value + "]" + equals + "]"
    raise ValueError("Unexpected long-string delimiter")


def main():
    src, dst = map(Path, sys.argv[1:3])
    lines = [
        "-- Descriptions recovered from this player's local beta quest cache.",
        "-- IDs are matched at import; no completion dates or NPC reward dialogue are inferred.",
        "FieldJournalQuestText = {",
    ]
    count = 0
    for quest_id, payload in records(src.read_bytes()):
        if quest_id not in QUESTS:
            continue
        try:
            description = extract(quest_id, payload)
        except ValueError as error:
            print(f"Skipped {quest_id}: {error}")
            continue
        lines.append(f"    [{quest_id}] = {lua_long_string(description)},")
        count += 1
    lines.append("}")
    dst.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {count} quest descriptions to {dst}")


if __name__ == "__main__":
    main()
