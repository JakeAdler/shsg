# shsg.sh

`shsg.sh` is a shell script for generating simple, static websites.

## [ [Installation](#installation) | [Configuration](#configuration) | [Usage](#usage) | [Credit](#Credit) ]

## Installation

First, create and cd into the directory where you'd like to store your project e.g. `~/my-site/`

```console
mkdir my-site && cd my-site
```

### Install the build script 

```console
# wget
wget https://raw.githubusercontent.com/JakeAdler/shsg/master/shsg.sh

# curl
curl -LJO https://raw.githubusercontent.com/JakeAdler/shsg/master/shsg.sh
```

### Give correct permssions

```console
chmod +x ./shsg.sh
```
## Configuration

After installing `shsg.sh`, open it in a text editor and make any necessary changes.

| Name              | Description                                     | Default     | Required                 |
|-------------------|-------------------------------------------------|-------------|--------------------------|
| `SRC_DIR`         | Where source files are located                  | "src"       | Yes                      |
| `OUT_DIR`         | Where output files are located                  | "public"    | Yes                      |
| `TEMPLATE_DIR`    | Where template files are located                | "templates" | Yes (If using templates) |
| `FORMAT_PRG`      | Command that will format outputted html files   | NONE        | No (Recommended)         |
| `FORMAT_PRG_ARGS` | Arguments/flags passed to `FORMAT_PRG`          | NONE        | No (Recommended)         |

Here are some reccomended configurations for `FORMAT_PRG` and `FORMAT_PRG_ARGS`

[Prettier](https://prettier.io/)
```sh
FORMAT_PRG="prettier"
FORMAT_PRG_ARGS="--stdin-filepath $TEMPLATE_OUT_PATH --parser html"
```

[tidy](https://www.html-tidy.org/)
```
FORMAT_PRG="tidy"
FORMAT_PRG_ARGS="-iq --tidy-mark no"
```


## Usage

- [Initialization](#initialization)
- [Writing markdown](#writing-markdown)
    - [Frontmatter](#frontmatter)
    - [Markdown syntax caveats](#markdown-syntax-caveats)
- [Other files](#other-files)
- [Using Templates](#using-templates)
    - [Setting template explicitly](#setting-template-explicitly)
    - [Setting template implicitly](#setting-template-implicitly)
    - [Templates and CSS](#templates-and-css)

## Initialization

Run `./shsg.sh init`, this will simply create the `SRC_DIR`, `OUT_DIR`, and `TEMPLATE_DIR` directories.

Your directory structure should now look like this:

```console
├── public
├── src
├── templates
└── shsg.sh
```

## Writing markdown

`shsg.sh` uses a slightly stripped down and modified version of [markdown.bash]() to parse markdown.

Most of the markdown spec is supported with some exceptions, see [caveats](#markdown-syntax-caveats).

### Frontmatter

Frontmatter in `shsg.sh` is very powerful, since everything between the YAML frontmatter delimiters (`---`) is treated as shell script.

For example:

Source file `src/blog/post-1.md`
```
---
TITLE="My first post"
---

# This is my blog

Some great content
```

Template file `templates/blog.html`
```html
<div>
    <h1>${TITLE}</h1>
    <div>${BODY}</div>
</div>
```

Will produce `public/blog/post-1.html`
```html
<div>
    <h1>My first post</h1>
    <div>
        <h1>This is my blog</h1>
        <p>Some great content</p>
    </div>
</div>
```
### Markdown syntax caveats

#### Multi-line blocks (``` | ~~~)

**Wont work:**
~~~md
Some JavaScript code
```
function add (a, b) {
    return a + b
}
```
~~~

**Will work:**
~~~md
Some JavaScript code
<pre><code>
function add (a, b) {
    return a + b
}
</code></pre>
~~~

#### Nested lists 

**Will work**
```md
- List
- Item
```

**Wont work**

```md
- List
- Item
    - Child

```

**Will work**
```md
<ul>
    <li> List </li>
    <li> Item </li>
    <ul>
        <li> Child </li>
    </ul>
</ul>
```

## Other files

All non-markdown files will be copied to the public directory, including HTML and css files.

## Using templates

Templates are HTML files which contain shell variables, these shell variables will be replaced by [frontmatter]() values, or in some special cases, by values set by `shsg.sh`.

Values set by `shsg.sh`:

| Name   | Description                                |
|--------|--------------------------------------------|
| `BODY` | Where the transpiled HTML will be inserted |

### Setting template explicitly

Templates can be explicitly set using [frontmatter](#frontmatter).

For example, using the following directory structure:

```console
├── public
├── src
│   └── about_me.md
├── templates
│   └── layout.html
└── shsg.sh
```

You can make `src/about_me.md.` use `templates/layout.html` by setting `TEMPLATE_FILE="templates/layout.html"` in the frontmatter of `src/about_me.md`.

`src/about_me.md`
```md
---
TEMPLATE_FILE="templates/layout.html"
---

Lorem ipsum dolor sit amet.
```

### Setting template implicitly

For each file in `TEMPLATE_DIR`, `shsg.sh` will look for a directory with a corresponding directory name, `templates/foo.html` would implicitly be used for all markdown file in `src/foo/*`.

For example, using the following directory structure:

```console
├── public
├── src
│   └── blog
│       └── post-1.md
├── templates
│   └── blog.html
└── shsg.sh
```

All files in `src/blog`, `post-1.md` will have it's template implicitly set to `templates/blog.html`.

#### Implicitly targeting nested directories

Typically, template files will correspond to a directory in `$SRC_DIR/$(basename TEMPLATE_FILE .html)` (e.g. `templates/blog` corresponds to `src/blog`). 

To target a nested directory (e.g `src/blog/special-posts/`), replace directory seperators (`/`) after `SRC_DIR` with underscores `_` (e.g. `templates/blog_special-posts.html`).

### Templates and CSS

Template files can have a CSS file with the same basename (e.g. `templates/home.html` and `templates/home.css`) that will be automatically copied once per directory that the template is used. This means that a file which explicitly sets it's template and is not inside the implicit template directory will have the CSS file copied to it's directory.

## Credit

- [chadbraunduin](https://github.com/chadbraunduin) for creating [markdown.bash](https://github.com/chadbraunduin/markdown.bash), which is used in the `parse_md` function.
- [cfenollosa](https://github.com/cfenollosa) for creating [bashblog](https://github.com/cfenollosa/bashblog), which served as an inspiration for this project.
