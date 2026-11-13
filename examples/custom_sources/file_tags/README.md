# File Tags Custom Source

This example generates three fictional IT support documents and applies different
file tags using the RAM Custom Source API. It demonstrates saving files and then
tagging them by their source filenames, including multiple tags on one file.

## How It Works

The entry point in [run.py](./run.py) writes three text files under `/tmp`
and saves each with `client.save_file(filepath)`. It then applies tags with
`client.add_tags_to_file(filename, tags)`, using the matching source filename
without the `/tmp/` prefix.
Each tag is a `SourceClient.FileTag` with a name and description.

The password reset guide receives both its topic tag and an onboarding tag in
the same tagging call. The files are written directly under `/tmp`, not inside
a randomly named temporary directory, to keep source filenames stable.

This example uses separate save and tag calls because `save_file(..., tags=...)`
was observed to produce an untagged file and a second, tagged file under a random
temporary path in the reported RAM runtime. This behavior may depend on the
runtime version; verify that synchronization produces only the three filenames
below with their expected tags.

| Source File | Tags |
| ----------- | ---- |
| `password_reset.txt` | `account-access`, `employee-onboarding` |
| `vpn_connection.txt` | `networking` |
| `laptop_replacement.txt` | `hardware` |

The example does not clear the source or delete unrelated files. It uses fixed
filenames and tag names rather than generating new names for each synchronization.
If earlier versions created entries such as `tmp.../password_reset.txt`, remove
those obsolete entries manually; this example does not clean them up.

## Setup

Follow the [general custom source instructions](../README.md):

1. Create a Custom Source template using [run.py](./run.py), then save and publish it.
2. Create a source from the template and synchronize it.
3. Inspect the source's files and confirm that their tags match the table above.
4. Add the source to a collection and vectorize it for retrieval.

No API keys, environment variables, LLM calls, or third-party packages are needed.
The example uses the Python standard library and `sasram` supplied by RAM.

## Adapting the Example

Replace `DOCUMENTS` with your own content, filenames, and tags. For files already
ingested into the source, use `client.add_tags_to_file` without uploading them again.
The API also provides `client.create_tag(tag)` to create a tag separately and
`client.untag_file(filename, tag_names)` to remove selected tags from a file.

File tags label whole documents. They are separate from the record-level
metadata filters demonstrated by the
[metadata filtering agent](../../agents/metadata_filtering_agent/).
This source demonstrates applying tags, not configuring agent retrieval filters.
