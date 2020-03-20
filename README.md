# Original Issue Linker

A tiny utility that helps `git subtree split` workflows.
Creates a new reference issue for each issue or PR from an original repository to destination repositories with the same number.

## Installing

```bash
curl -LO https://raw.githubusercontent.com/bellface/original-issue-linker/master/link.sh
chmod +x link.sh
```

## Usage

<img width="425" alt="" src="https://user-images.githubusercontent.com/1351893/77214345-11e60900-6b52-11ea-9d1b-66be8163162c.png">
<img width="418" alt="" src="https://user-images.githubusercontent.com/1351893/77214347-13173600-6b52-11ea-88fa-f37deb55636d.png">

```bash
GITHUB_TOKEN=XXXXXXX ./link.sh user/source user/destination_1 user/destination_2 ...
```

## Options

You can pass some options via environment variables.

```bash
BASE_URI=${BASE_URI:-https://api.github.com}
START_PAGE=${START_PAGE:-1}
TITLE_FORMAT=${TITLE_FORMAT:-[OLD] %s}
REFERENCE_FORMAT=${REFERENCE_FORMAT:-This is a reference to %s.}
ISSUE_LABEL=${ISSUE_LABEL:-Old Issue Reference}
```
