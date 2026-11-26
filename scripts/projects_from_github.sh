#!/usr/bin/env bash
# =============================================================================
# projects_from_github.sh: write the list of repositories the site shows
# =============================================================================
#
# GitHub is the list. This script asks GitHub for the account's PUBLIC
# repositories and writes two pieces of Markdown that the pages include:
#
#   _projects.md   every listed repository, under its group's heading
#   _recent.md     the few most recently updated, for the home page
#
# A repository is listed when all of these hold:
#   - it is public (the listing asked for holds nothing else, and the script
#     stops if it ever does);
#   - it carries exactly one of the group topics named in projects.yml;
#   - it has a description on GitHub, which is the text shown;
#   - it is not a fork and not archived.
#
# Usage, from the repository's folder:
#   bash scripts/projects_from_github.sh                 ask GitHub (needs gh)
#   bash scripts/projects_from_github.sh --from FILE     read a saved listing instead
#   options: --config FILE (default projects.yml), --out FOLDER (default .)
#
# Nothing is written unless every check passes.

set -euo pipefail

CONFIG="projects.yml"
FROM=""
OUT="."

# stop WHAT WHERE EXPECTED FIX: say what is wrong in four parts, and end
stop() {
    {
        echo "FATAL: the list of projects was not written."
        echo "  What:     $1"
        echo "  Where:    $2"
        echo "  Expected: $3"
        echo "  Fix:      $4"
    } >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config | --from | --out)
            [[ $# -ge 2 ]] || stop "$1 was given no value" "the command line" \
                "$1 followed by a path" "give the path after $1"
            case "$1" in
                --config) CONFIG="$2" ;;
                --from) FROM="$2" ;;
                --out) OUT="$2" ;;
            esac
            shift 2
            ;;
        *)
            stop "'$1' is not an option of this script" "the command line" \
                "any of --config FILE, --from FILE, --out FOLDER" "remove '$1'"
            ;;
    esac
done

for tool in jq yq; do
    command -v "$tool" > /dev/null || stop "the program '$tool' is not installed" "this machine's PATH" \
        "jq and yq, both on the PATH" "brew install $tool"
done
[[ -f "$CONFIG" ]] || stop "the settings file is missing" "$CONFIG" \
    "a YAML file with owner, recent and groups" "run the script from the repository's folder"
[[ -d "$OUT" ]] || stop "the folder to write to does not exist" "$OUT" "an existing folder" "create it, or change --out"

# ----------------------------------------------------------------------------
# The settings: whose repositories, how many on the home page, and the groups
# ----------------------------------------------------------------------------
SETTINGS="$(yq -o=json '.' "$CONFIG")"
if ! jq -e '(.owner | type == "string") and (.recent | type == "number") and (.groups | type == "array")
            and (.groups | length > 0)
            and (.groups | all(has("topic") and has("heading")))' <<< "$SETTINGS" > /dev/null; then
    stop "the settings are incomplete" "$CONFIG" \
        "owner: a GitHub account; recent: a number; groups: a list of entries, each with topic and heading" \
        "compare $CONFIG with the copy in the repository's history"
fi
OWNER="$(jq -r '.owner' <<< "$SETTINGS")"
GROUP_TOPICS="$(jq -r '[.groups[].topic] | join(", ")' <<< "$SETTINGS")"

# ----------------------------------------------------------------------------
# The listing: what anyone can see of the account, and nothing more
# ----------------------------------------------------------------------------
# users/OWNER/repos is GitHub's public listing: it returns public repositories
# only, whoever asks. --paginate gives one JSON array for each page of a
# hundred; `jq -s add` joins them into one.
if [[ -n "$FROM" ]]; then
    [[ -f "$FROM" ]] || stop "the saved listing is missing" "$FROM" "a JSON file" "check the path given to --from"
    WHERE="$FROM"
    RAW="$(cat "$FROM")"
else
    command -v gh > /dev/null || stop "the program 'gh' is not installed" "this machine's PATH" \
        "the GitHub command-line tool" "brew install gh, or give a saved listing with --from"
    WHERE="GitHub's public listing for $OWNER"
    RAW="$(gh api --paginate "users/$OWNER/repos?per_page=100&type=owner")" ||
        stop "GitHub did not answer" "$WHERE" "a list of repositories" "run it again; check 'gh auth status'"
fi
LISTING="$(jq -s 'if all(type == "array") then add else . end' <<< "$RAW" 2> /dev/null)" || LISTING="null"
jq -e 'type == "array" and all(type == "object" and has("name") and has("topics"))' <<< "$LISTING" > /dev/null ||
    stop "the answer is not a list of repositories" "$WHERE" \
        "a JSON list in which every entry has a name and its topics" \
        "look at the answer: it may be an error message from GitHub, such as a rate limit"

# ----------------------------------------------------------------------------
# Check 1: nothing that is not public, whether or not it would be listed
# ----------------------------------------------------------------------------
NOT_PUBLIC="$(jq -r '[.[] | select(.private != false or .visibility != "public") | .name] | join(", ")' <<< "$LISTING")"
[[ -z "$NOT_PUBLIC" ]] || stop "the listing holds repositories that are not public: $NOT_PUBLIC" "$WHERE" \
    "public repositories only: private is false and visibility is public for every entry" \
    "do not publish; find out why a private repository is in a public listing before running this again"

# ----------------------------------------------------------------------------
# Which repositories are listed: one group topic, not a fork, not archived
# ----------------------------------------------------------------------------
LISTED="$(jq --argjson settings "$SETTINGS" '
    ($settings.groups | map(.topic)) as $group_topics
    | [ .[]
        | select((.fork | not) and (.archived | not))
        | . + {groups: [.topics[] | select(. as $t | $group_topics | index($t))]}
        | select(.groups | length > 0) ]' <<< "$LISTING")"

IN_TWO="$(jq -r '[.[] | select(.groups | length > 1) | "\(.name) (\(.groups | join(", ")))"] | join("; ")' <<< "$LISTED")"
[[ -z "$IN_TWO" ]] || stop "a repository carries more than one group topic: $IN_TWO" "the topics of that repository on GitHub" \
    "exactly one of: $GROUP_TOPICS" "remove one: gh repo edit $OWNER/NAME --remove-topic TOPIC"

UNDESCRIBED="$(jq -r '[.[] | select((.description // "") | test("^\\s*$")) | .name] | join(", ")' <<< "$LISTED")"
[[ -z "$UNDESCRIBED" ]] || stop "a listed repository has no description: $UNDESCRIBED" \
    "the description of that repository on GitHub" "one sentence saying what the repository is" \
    "gh repo edit $OWNER/NAME --description \"...\", or remove its group topic to leave it off the site"

[[ "$(jq 'length' <<< "$LISTED")" -gt 0 ]] || stop "no repository carries a group topic, so there is nothing to show" \
    "the topics of the public repositories of $OWNER" "at least one repository with one of: $GROUP_TOPICS" \
    "gh repo edit $OWNER/NAME --add-topic TOPIC"

# ----------------------------------------------------------------------------
# Write the two pieces of Markdown
# ----------------------------------------------------------------------------
# One line for each repository:
#   - **[name](link)**: The description. *Python, updated 26 November 2026.*
# Characters that Markdown would act on are escaped in the description, since
# it is text typed on GitHub and not Markdown.
ENTRY='
    def escaped: gsub("(?<c>[\\\\*_\\[\\]<>$`{}|~^#@])"; "\\\(.c)");
    def sentence: gsub("^\\s+|\\s+$"; "") | if test("[.!?]$") then . else . + "." end;
    def entry:
        (.pushed_at | fromdateiso8601 | strftime("%-d %B %Y")) as $date
        | "- **[\(.name)](\(.html_url))**: \(.description | sentence | escaped) "
          + (if .language then "*\(.language), updated \($date).*" else "*Updated \($date).*" end);
'
PROJECTS="$(jq -r --argjson settings "$SETTINGS" "$ENTRY"'
    . as $listed
    | $settings.groups[]
    | . as $group
    | [$listed[] | select(.groups[0] == $group.topic)]
    | select(length > 0)
    | "## \($group.heading)\n\n" + (sort_by(.pushed_at) | reverse | map(entry) | join("\n")) + "\n"' <<< "$LISTED")"
RECENT="$(jq -r --argjson settings "$SETTINGS" "$ENTRY"'
    sort_by(.pushed_at) | reverse | .[:$settings.recent] | map(entry) | join("\n")' <<< "$LISTED")"

printf '%s\n' "$PROJECTS" > "$OUT/_projects.md"
printf '%s\n' "$RECENT" > "$OUT/_recent.md"

echo "$(jq 'length' <<< "$LISTED") repositories listed, from $(jq 'length' <<< "$LISTING") public ones of $OWNER."
echo "Public but not listed (no group topic, a fork, or archived):"
jq -r --argjson listed "$LISTED" '[.[].name] - [$listed[].name] | "  " + join(", ")' <<< "$LISTING"
