#!/usr/bin/env python3
"""Bidirectional sync: CouchDB LiveSync <-> VPS obsidian-vault files.

Pull: CouchDB -> VPS files (for files created on local/mobile Obsidian)
Push: VPS files -> CouchDB (for files created by OpenClaw skills)
Runs every 5 min via cron.
"""
import json
import os
import hashlib
import urllib.request
import urllib.parse
import base64
import time

COUCH_URL = "http://127.0.0.1:5984/obsidianvault"
COUCH_CREDS = base64.b64encode(b"obsidian:011RKOAuv8p7vny13nYB").decode()
VAULT = os.path.expanduser("~/obsidian-vault")
STATE_FILE = os.path.expanduser("~/.openclaw/skills/memory/sync-vault-state.json")

def couch_request(url, method="GET", data=None):
    """Make authenticated CouchDB request."""
    try:
        req = urllib.request.Request(url, method=method)
        req.add_header("Authorization", "Basic " + COUCH_CREDS)
        if data is not None:
            req.add_header("Content-Type", "application/json")
            req.data = json.dumps(data).encode()
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 409:
            return {"error": "conflict"}
        return None
    except Exception:
        return None

def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"pushed_files": {}, "last_pull_seq": "0"}

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def xxhash_simple(data):
    """Simple hash for file ID generation (matching LiveSync's format)."""
    return hashlib.sha256(data.encode()).hexdigest()[:58]

def pull_from_couch():
    """Pull files from CouchDB to VPS vault."""
    all_docs = couch_request(f"{COUCH_URL}/_all_docs")
    if not all_docs:
        print("PULL: Failed to fetch docs")
        return 0

    file_ids = [r["id"] for r in all_docs["rows"] if r["id"].startswith("f:")]
    synced = 0

    for fid in file_ids:
        doc = couch_request(f"{COUCH_URL}/{urllib.parse.quote(fid, safe='')}")
        if not doc:
            continue

        path = doc.get("path", "")
        if not path or path.startswith("/\\:%="):
            continue

        # Reassemble content from chunks
        children = doc.get("children", [])
        content = ""
        for cid in children:
            chunk = couch_request(f"{COUCH_URL}/{urllib.parse.quote(cid, safe='')}")
            if chunk and "data" in chunk:
                content += chunk["data"]

        if not content:
            continue

        full_path = os.path.join(VAULT, path)

        # Only write if content differs
        try:
            with open(full_path, "r") as f:
                if f.read() == content:
                    continue
        except (FileNotFoundError, UnicodeDecodeError):
            pass

        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "w") as f:
            f.write(content)
        synced += 1

    return synced

def push_to_couch():
    """Push new/changed VPS files to CouchDB for sync to local/mobile."""
    state = load_state()
    pushed = state.get("pushed_files", {})

    # Collect all existing CouchDB file paths
    all_docs = couch_request(f"{COUCH_URL}/_all_docs")
    if not all_docs:
        print("PUSH: Failed to fetch docs")
        return 0

    couch_paths = set()
    for row in all_docs["rows"]:
        if row["id"].startswith("f:"):
            doc = couch_request(f"{COUCH_URL}/{urllib.parse.quote(row['id'], safe='')}")
            if doc and doc.get("path"):
                couch_paths.add(doc["path"])

    synced = 0
    for root, dirs, files in os.walk(VAULT):
        # Skip hidden dirs
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fname in files:
            if not fname.endswith(".md"):
                continue

            full_path = os.path.join(root, fname)
            rel_path = os.path.relpath(full_path, VAULT)

            # Skip if already in CouchDB
            if rel_path in couch_paths:
                continue

            # Read file content
            try:
                with open(full_path, "r") as f:
                    content = f.read()
            except Exception:
                continue

            if not content.strip():
                continue

            # Check if we already pushed this exact content
            content_hash = hashlib.md5(content.encode()).hexdigest()[:16]
            if pushed.get(rel_path) == content_hash:
                continue

            # Create chunk document
            chunk_id = "h:" + xxhash_simple(content)
            chunk_doc = couch_request(f"{COUCH_URL}/{urllib.parse.quote(chunk_id, safe='')}")
            
            if not chunk_doc or "error" in chunk_doc:
                # Create new chunk
                result = couch_request(
                    f"{COUCH_URL}/{urllib.parse.quote(chunk_id, safe='')}",
                    method="PUT",
                    data={"data": content, "type": "leaf"}
                )
                if not result or "error" in result:
                    continue

            # Create file document
            file_id = "f:" + xxhash_simple(rel_path + str(time.time()))
            mtime = int(os.path.getmtime(full_path) * 1000)
            ctime = int(os.path.getctime(full_path) * 1000)
            
            file_doc = {
                "path": rel_path,
                "children": [chunk_id],
                "ctime": ctime,
                "mtime": mtime,
                "size": len(content.encode()),
                "type": "newnote"
            }
            
            result = couch_request(
                f"{COUCH_URL}/{urllib.parse.quote(file_id, safe='')}",
                method="PUT",
                data=file_doc
            )
            
            if result and "error" not in result:
                pushed[rel_path] = content_hash
                synced += 1

    state["pushed_files"] = pushed
    save_state(state)
    return synced

def main():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Vault sync starting...")
    
    pulled = pull_from_couch()
    print(f"  PULL: {pulled} files updated from CouchDB")
    
    pushed = push_to_couch()
    print(f"  PUSH: {pushed} new files sent to CouchDB")
    
    if pulled == 0 and pushed == 0:
        print("  Everything in sync.")

if __name__ == "__main__":
    main()
