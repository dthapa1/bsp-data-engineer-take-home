"""
PawsFirst Veterinary Warehouse — Common Utilities

Shared connection helpers and configuration used across all flows.
"""

from __future__ import annotations

from pathlib import Path

import duckdb

DATABASE_PATH = Path(__file__).parent.parent / "data" / "pawsfirst.duckdb"
DATA_DIR = Path(__file__).parent.parent / "data"


def get_connection() -> duckdb.DuckDBPyConnection:
    """
    Get a DuckDB connection to the local warehouse.

    All flows must use this function — never hardcode the database path.
    """
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    return duckdb.connect(str(DATABASE_PATH))


def ensure_schemas(con: duckdb.DuckDBPyConnection) -> None:
    """Create the warehouse schemas if they don't exist."""
    for schema in ("bronze", "silver", "gold"):
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")


def run_migration(con: duckdb.DuckDBPyConnection, migration_path: str) -> None:
    """Execute a SQL migration file."""
    sql = Path(migration_path).read_text()
    
    # Remove line comments (-- ...) to avoid semicolons in comments breaking parsing
    lines = []
    for line in sql.split("\n"):
        # Find the position of -- comment marker (not in strings)
        in_string = False
        quote_char = None
        comment_pos = -1
        for i, char in enumerate(line):
            if char in ("'", '"') and (i == 0 or line[i-1] != "\\"):
                if not in_string:
                    in_string = True
                    quote_char = char
                elif char == quote_char:
                    in_string = False
            elif not in_string and i < len(line) - 1 and char == "-" and line[i+1] == "-":
                comment_pos = i
                break
        if comment_pos >= 0:
            lines.append(line[:comment_pos])
        else:
            lines.append(line)
    
    sql = "\n".join(lines)
    
    phases = sql.split("-- PHASE_BREAK")
    for phase in phases:
        phase = phase.strip()
        if not phase:
            continue
        statements = [s.strip() for s in phase.split(";") if s.strip()]
        for stmt in statements:
            if stmt.startswith("--"):
                continue
            con.execute(stmt)
