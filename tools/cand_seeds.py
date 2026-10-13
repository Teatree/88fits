"""Candidate seeds (pass 70, lane LE): every candidate tool paints candidate k of a job on a seed of its own, far from
candidate k-1, and every job (and every re-run of one) on seeds no other job of the same hero or look used.

Garry (2026-10-13): "When making multiple candidates always use a different seed for them, otherwise it's just the same
(almost same) art asset as many times as specified for the candidate." What was found:
  - Within one job the seeds already differed (badges k*1000 apart, title cut-outs k*101, icons k*7919, fronts from a
    picture k*1000): ComfyUI's RandomNoise draws an unrelated noise for any other seed, so the spacing was never the
    cause. The candidates look alike because every candidate is an edit of one reference picture (ReferenceLatent) on a
    distilled few-step model (Klein 4 passes, dev Turbo 8): the reference fixes the pose, the framing and the colours,
    and a title cut-out asked for the reference's own pose ("standing confidently") comes back as the reference.
  - Across jobs the seeds were the SAME: a second badge job for MAY-E painted 2768, 3768, 4768 again (j..b9ac and
    j..aca1), every title job for a hero's base painted 11, 112, 213, 314, every icon job of one key the same four, and a
    front from a picture always seed_for(id + slug) + 1000 k. "Generate some more" with a word changed gave the earlier
    pictures back, nearly.
  - A re-run of a front from a picture gave the very same files back: gen_edit_stills's candidates are cached by name
    (<id>_<slug>_front_c<k>) and nothing moved them aside.
So: candidate k sits CAND_STEP (a prime past a million) from k-1, a job's seeds are moved by its own id (job_salt: the
Level Editor job id, crc32, times JOB_STEP), a re-run by its attempt, and gen_edit_stills moves its earlier candidates
aside before it paints. A hand run (no job id) keeps base + k * CAND_STEP.
"""
import os
import re
import zlib

CAND_STEP = 1000003      # a prime: candidate k of a job sits this far from candidate k-1
JOB_STEP = 15485863      # a prime (the millionth): one job's seeds from another's
JOB_SLOTS = 49999        # job_salt's spread: crc32(job id) % JOB_SLOTS + 1 steps of JOB_STEP


def job_salt(tag):
    """How far a job's seeds move: 0 by hand (no tag, or the hand runs' "x"), else (crc32(tag) % JOB_SLOTS + 1) * JOB_STEP
    from the Level Editor job id (letters and digits; the whole id, not the four letters the files are named by)."""
    t = re.sub(r"[^A-Za-z0-9]", "", str(tag or ""))
    if not t or t.lower() == "x":
        return 0
    return (zlib.crc32(t.encode("ascii")) % JOB_SLOTS + 1) * JOB_STEP


def job_tag(tag=None):
    """The tag a run's seeds follow: the one given, else the Level Editor job it runs under (ASSET_JOB_ID), else ""."""
    return str(tag) if tag else os.environ.get("ASSET_JOB_ID", "")


def job_attempt(attempt=None):
    """A re-run's number: the one given, else the job's (ASSET_JOB_ATTEMPT, set by tools/asset_job.py from job.json),
    else 1."""
    for v in (attempt, os.environ.get("ASSET_JOB_ATTEMPT")):
        try:
            if v not in (None, ""):
                return max(1, int(v))
        except (TypeError, ValueError):
            pass
    return 1


def start(own, first=0):
    """Where a job's seeds start (pass 72, Garry: "first seed" on every asset that has candidates): the job's "First seed"
    when it names one (any whole number but 0), else the tool's own start `own` (from the asset's id). Every candidate
    tool takes its base through here; the look's offset, a re-run's attempt and the job id (seeds) move it on as before."""
    try:
        f = int(first or 0)
    except (TypeError, ValueError):
        f = 0
    return f if f else int(own)


def seeds(base, n, tag=""):
    """Candidate k's seed: base + job_salt(tag) + k * CAND_STEP, for k in 0..n-1 (base already holds the tool's own moves:
    the look's seed_offset, the attempt)."""
    move = int(base) + job_salt(tag)
    return [move + CAND_STEP * k for k in range(int(n))]


def all_apart(seed_list):
    """True when every two seeds of the list differ by at least CAND_STEP (the self-test's check)."""
    s = sorted(int(x) for x in seed_list)
    return all(b - a >= CAND_STEP for a, b in zip(s, s[1:]))
