# shsg.sh (shell site generator)

`shsg.sh` is a shell script for generating static websites from markdown.

## [ [Installation](#installation) | [Configuration](#configuration) | [Usage](#usage) ]

## Installation

### Before installing

Create and cd into the directory where you'd like to store your project e.g. `~/my-site/`

```console
mkdir my-site && cd my-site
```
### Install the script 

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

| name                 | description                                           | default     | required |
|----------------------|-------------------------------------------------------|-------------|----------|
| `SRC_DIR`            | where source files are located                        | "src"       | yes      |
| `OUT_DIR`            | where output files are located                        | "public"    | yes      |
| `TEMPLATE_DIR`       | where template files are located                      | "templates" | yes      |
| `QUIET`              | quiet mode                                            | false       | yes      |
| `CLEAR_BEFORE_BUILD` | clear terminal before building.                       | false       | yes      |
| `CACHE_DIR`          | where cached source files will be located             | NONE        | no       |
| `PARSER_CMD`         | command that will parse markdown into html            | NONE        | no       |
| `FORMAT_CMD`         | command that will format outputted html files         | NONE        | no       |
| `BASE_TEMPLATE`      | template from which all other will inherit            | NONE        | no       |
| `IGNORE_FILE`        | file containing list of paths `shsg.sh` should ignore | NONE        | no       |

#### Example configuration

[Pandoc](https://pandoc.org/)

```sh
readonly PARSER_CMD="pandoc --wrap=preserve -f gfm -t html"
```

## Usage

### CLI


```
./shsg.sh [COMMAND] [OPTIONS]

Commands
    init				create SRC_DIR, OUT_DIR, and TEMPLATE_DIR
    serve				run SERVE_CMD
    build				build all files in SRC_DIR
	build-file [FILE]	build FILE

Options
    -h      print this message
    -q      quiet mode - silence output
    -v      verbose mode - print output about all files
    -c      clean mode - remove everything in OUT_DIR before build.

```

### Initialization

Run `./shsg.sh init`, this will simply create the `SRC_DIR`, `OUT_DIR`, and `TEMPLATE_DIR` directories, if they do not already exist.

Your directory structure should now look like this:

```console
├── public
├── src
├── templates
└── shsg.sh
```

### Templates

Templates are HTML files inside of `TEMPLATE_DIR` which contain shell style variable references, for example:

```html
<div>
    ${BODY}
</div>
```

Templates are only useful when combined with source files, though. We can target source files in 2 ways: **implicitly** and **explicitly**. 

### Targeting source files implicitly

Implicit targeting is useful for targeting whole directories, for example:

```
├── src
│   ├── blog
│   │   ├── index.html
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── index.html
└── templates
    └── blog.html

```

The template file `template/blog.html` would target `src/blog/index.html`, `src/blog/post-1.md`, and `src/blog/post-2.md`.

```
templates/[NAME].html ---> src/[NAME]/*
```


### Targeting source files explicitly

If we wanted to use a different template for `blog/index.html`, we could do that by creating a template that explicitly targets that file.

```
├── src
│   ├── blog
│   │   ├── index.html
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── index.html
└── templates
    ├── blog
    │   └── __index.html
    └── blog.html

```

Since `templates/blog/__index.html` is prefixed with 2 underscores, it explicitly targets the file `src/blog/index.html`. 

```
templates/[__NAME].html --> src/[NAME].(html|md)
```

### Index templates

Notice how the template file structure is a bit ugly? There is a file `blog.html` and a directory name `blog`. We can clean this up a bit by moving `templates/blog.html` --> `templates/blog/index.html`.

```
├── src
│   ├── blog
│   │   ├── index.html
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── index.html
└── templates
    └── blog
        ├── __index.html
        └── index.html
```

Now we have 2 files in `templates/blog`: `__index.html` which explicitly targets `src/blog/index.html`, and `index.html` which servers as the default template and will target all other files in `src/blog`.

### Templates and CSS

Template files can have a CSS file with the same basename (e.g. `templates/home.html` and `templates/home.css`) that will be automatically copied once per directory that the template is used. This means that a file which explicitly sets it's template and is not inside the implicit template directory will have the CSS file copied to it's directory.

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

Template file `templates/blog/index.html`
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

#### HTML frontmatter

In `shsg.sh`, HTML files can have frontmatter too:

`src/blog/post-1.html`
```
<!--FM
TITLE="My first post"
-->

<h1>This is my blog</h1>
<p>Some great content</p>
```
There are a few values which can be set in frontmatter that will effect how the file gets built:


#### Frontmatter build variables

| Name                | Description                                                                 |
|---------------------|-----------------------------------------------------------------------------|
| `TEMPLATE_FILE`     | Relative path from root (e.g. `templates/blog.html`) to template HTML file. |
| `TEMPLATE_FILE_CSS` | Relative path from root(e.g. `templates/blog.css` to template CSS file.     |
| `BODY`              | Body of the markdown file (value is only read if `SAFE_BODY` is false)      |

All internal variables in `shsg.sh` that are not supposed to be overriden are prefixed with `__`. Because of how shell scripting works, any value in the script can be overriden, to avoid doing that, avoid prefixing your own variables in frontmatter with `__`.

### Other files

All non-markdown files will be copied to the public directory, unless they are listed in `IGNORE_FILE`.

### Template inheritance

Templates can be inherit one another by adding the following HTML comment as the **first line** of a template file.

```
<!-- INHERITS path/to/template.html -->
```

The path should be relative from the root project directory, e.g.:

```
<!-- INHERITS templates/parent.html -->

```

Note: this line should **not** be incuded in a HTML frontmatter block.

When a template inherits another, the `BODY` section of the parent template is replaced with the child template.

For example:

`templates/html-doc.html`
```html
<html>
    <body>
        ${BODY}
    </body>
<html>
```

`templates/blog.html`
```html
<!-- INHERITS templates/html-doc.html -->
<div>
    <h1>${TITLE}</h1>
    <div>
        ${BODY}
    </div>
<div>
```
Would produce the template
```html
<html>
    <body>
        <div>
            <h1>${TITLE}</h1>
            <div>
                ${BODY}
            </div>
        <div>
    </body>
<html>
```

### Note on `BASE_TEMPLATE`

In the above example, `templates/html-doc.html` only exists to be inherited, there are not any files it is targeting specifically. Therefore it is a good candidate for `BASE_TEMPLATE`. Do note that **all templates** will inherit this template.
