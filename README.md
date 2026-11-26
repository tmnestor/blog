# blog

The source of <https://tmnestor.github.io/blog/>: a home page, a Projects page that lists my public
repositories, and a Sailing page.

It is a [Quarto](https://quarto.org) website. The pages are Markdown, and GitHub builds and publishes
the site.

## What is here

| File | What it is |
|---|---|
| `index.qmd` | The home page |
| `projects.qmd` | The Projects page: a few words, then the list the script writes |
| `sailing.qmd` | The Sailing page |
| `_quarto.yml` | The site's title, menu and theme |
| `projects.yml` | Whose repositories are listed, and the groups they are listed under |
| `scripts/projects_from_github.sh` | Asks GitHub for the public repositories and writes the list |
| `.github/workflows/publish.yml` | Builds and publishes the site |

## How a repository gets onto the Projects page

GitHub is the list: nothing about a repository is written in this repository.

A repository is listed when all of these hold:

1. It is **public**. The script asks GitHub's public listing, which holds nothing else, and stops
   without publishing if a repository that is not public is ever in the answer.
2. It carries **exactly one group topic**: one of the topics in `projects.yml`.
3. It has a **description** on GitHub. That sentence is the text shown.
4. It is not a fork and not archived.

So, to show a repository:

```bash
gh repo edit tmnestor/NAME --description "One sentence saying what it is" --add-topic tools
```

To take one off the page, remove its group topic:

```bash
gh repo edit tmnestor/NAME --remove-topic tools
```

To add a group, or change a heading or the order of the groups, edit `projects.yml`.

A repository with a group topic and no description stops the build, with a message that names it. So
does one with two group topics.

## When the site is rebuilt

- On every push to `main`.
- Once a week, so a change to a repository's description or topic appears without anything being
  pushed here.
- By hand: the Actions tab, "Publish the site", "Run workflow".

GitHub switches a weekly schedule off after 60 days without activity in a public repository. Each run
enables the workflow again to renew it. If the weekly run ever stops all the same, GitHub says so on
the Actions tab, and "Enable workflow" there starts it again.

## Seeing a change before it is published

```bash
bash scripts/projects_from_github.sh    # writes _projects.md and _recent.md from GitHub
quarto preview                          # opens the site in a browser and follows edits
```

Both files the script writes are ignored by git: they are made again at every build.

## Writing in Sailing

`sailing.qmd` is Markdown. For more than one piece, make a folder `sailing/` with a file for each,
and turn `sailing.qmd` into a [listing](https://quarto.org/docs/websites/website-listings.html) of that
folder.
