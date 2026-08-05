import Foundation

// MARK: - Three-Way Merge

/// Line-based 3-way merge for the conflict engine (editor epic G3, US-3.1).
///
/// Given the last content known to be on disk (`base`), the user's live model
/// (`mine`), and fresh external content (`theirs`), produces a clean merge when
/// the two sides changed disjoint line regions, and reports a clash — never a
/// silent resolution — when they touched the same region (D7).
///
/// Lines are opaque: CRLF documents keep their `\r` inside each line, and
/// splitting/joining on `\n` is lossless, so merged output preserves the
/// original bytes of every untouched region (BRD guardrail 4).
public enum ThreeWayMerge {

    public enum Result: Equatable {
        /// Both sides' edits survive in the returned content.
        case merged(String)
        /// Same-region edits differ — the caller must ask the user.
        case clash
    }

    public static func merge(base: String, mine: String, theirs: String) -> Result {
        // Trivial cases: only one side moved, or both made the same change.
        if mine == theirs { return .merged(mine) }
        if theirs == base { return .merged(mine) }
        if mine == base { return .merged(theirs) }

        // components(separatedBy:), not split(separator:): Swift Characters
        // are grapheme clusters, so CRLF is ONE Character and split on "\n"
        // would never divide a CRLF document. Foundation splits on the
        // literal UTF-16 unit and round-trips losslessly.
        let baseLines = base.components(separatedBy: "\n")
        let mineHunks = hunks(base: baseLines, other: mine.components(separatedBy: "\n"))
        let theirHunks = hunks(base: baseLines, other: theirs.components(separatedBy: "\n"))

        guard let combined = combine(mineHunks, theirHunks) else { return .clash }

        var merged: [String] = []
        var cursor = 0
        for hunk in combined {
            merged.append(contentsOf: baseLines[cursor..<hunk.baseRange.lowerBound])
            merged.append(contentsOf: hunk.lines)
            cursor = hunk.baseRange.upperBound
        }
        merged.append(contentsOf: baseLines[cursor...])
        return .merged(merged.joined(separator: "\n"))
    }

    // MARK: - Hunks

    /// One side's edit: replace `baseRange` (line indices) with `lines`.
    /// An insertion is an empty `baseRange` at the insertion point.
    private struct Hunk {
        let baseRange: Range<Int>
        let lines: [String]
    }

    /// Derives replacement hunks from the base→other line diff. Lines the
    /// diff kept on both sides anchor the hunks; everything between two
    /// anchors is a single replacement.
    private static func hunks(base: [String], other: [String]) -> [Hunk] {
        let diff = other.difference(from: base)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let baseKept = (0..<base.count).filter { !removed.contains($0) }
        let otherKept = (0..<other.count).filter { !inserted.contains($0) }

        var result: [Hunk] = []
        var prevBase = -1
        var prevOther = -1
        for (b, o) in Array(zip(baseKept, otherKept)) + [(base.count, other.count)] {
            let baseGap = (prevBase + 1)..<b
            let otherGap = (prevOther + 1)..<o
            if !baseGap.isEmpty || !otherGap.isEmpty {
                result.append(Hunk(baseRange: baseGap, lines: Array(other[otherGap])))
            }
            prevBase = b
            prevOther = o
        }
        return result
    }

    /// Interleaves both sides' hunks by base position. Returns nil on any
    /// same-region clash: overlapping base ranges with different outcomes,
    /// or competing insertions at the same point. Identical edits from both
    /// sides collapse into one.
    private static func combine(_ mine: [Hunk], _ theirs: [Hunk]) -> [Hunk]? {
        var combined: [Hunk] = []
        var m = 0
        var t = 0
        while m < mine.count || t < theirs.count {
            if m < mine.count && t < theirs.count {
                let a = mine[m]
                let b = theirs[t]
                let identical = a.baseRange == b.baseRange && a.lines == b.lines
                if identical {
                    combined.append(a); m += 1; t += 1; continue
                }
                let overlap = a.baseRange.lowerBound < b.baseRange.upperBound
                    && b.baseRange.lowerBound < a.baseRange.upperBound
                let competingInsert = a.baseRange.isEmpty && b.baseRange.isEmpty
                    && a.baseRange.lowerBound == b.baseRange.lowerBound
                if overlap || competingInsert { return nil }
                if (a.baseRange.lowerBound, a.baseRange.upperBound)
                    < (b.baseRange.lowerBound, b.baseRange.upperBound) {
                    combined.append(a); m += 1
                } else {
                    combined.append(b); t += 1
                }
            } else if m < mine.count {
                combined.append(mine[m]); m += 1
            } else {
                combined.append(theirs[t]); t += 1
            }
        }
        return combined
    }
}
