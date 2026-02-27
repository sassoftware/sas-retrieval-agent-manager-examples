# Using the SAS Open Source Project Starter Kit
This kit contains resources for creating repositories that comply with SAS's requirements for open source projects.

## About the Kit's Components
The starter kit contains the following components.

### README.md
Open source projects should be useful, so include a README file to help people get started using yours.
The README file included in the project starter kit is annotated with guidelines for using it.
Some sections of the template are required; others are optional.
Additional project documentation will likely be useful (please see the kit's documentation resources), but a README file is the minimum you should offer.

### CONTRIBUTING.md and ContributorAgreement.txt
The starter kit includes a basic `CONTRIBUTING.md` file outlining the minimal contribution guidelines your project should offer.
The file is annotated.
Every project that accepts contributions must include this file, along with the standard ContributorAgreement.txt file, which is also included in this kit.
If your project will accept contributions and patches from external community contributors, then edit this file to say so.
If your project will not accept contributions and patches from external community contributors, likewise edit this file to say so.

### SUPPORT.md
The starter kit includes a standard `SUPPORT.md` file that directs users to use GitHub issues and pull requests to seek support.
Any alternate means of providing support for your project requires approval from SAS Legal and Technical Support.
Discuss this with the Open Source Program Office prior to publishing your project on GitHub.

### SECURITY.md
Use this file if you plan to activate GitHub's private security vulnerability reporting for public projects.
The file is annotated with instructions for using this feature.
Modify the file to reflect your project's security posture.

### LICENSE
Your project must contain a file named LICENSE in its top-level directory.
The file must contain a copy of the project's license.
The starter kit contains a copy of SAS's default open source license, the Apache License version 2.0.

## Creating Project Documentation
The starter kit contains resources for building project documentation that complies with SAS brand standards.
This documentation is built and served with the [Docusaurus](https://docusaurus.io/) website generator.
If you would like to use these documentation materials, edit the `website/docusaurus.config.ts` file in order to replace `<projectName>` with your project name.

> [!NOTE]
> The `docusaurus.config.ts` file contains multiple instances of this variable; be sure to locate and change them all.

Add Markdown files to `website/docs` to begin creating project documentation.
The website is automatically rebuilt when changes to these files are merged to the project's `main` branch.
See its [README](./website/README.md) for details.

See project documentation for the [SAS extension for Visual Studio Code](https://github.com/sassoftware/vscode-sas-extension/tree/main/website) for an example.

## Preparing Your Project for Review
When development is complete, your project will undergo final reviews and approvals.
Everything required for using and reviewing your project should be included in the repository, including relevant build and execution instructions.
To ensure timely review of your work, complete these preparation steps.

### Add source code headers
Every file containing source code must include copyright and license information.
Place required source code headers at the top of the source code files, above any other header information.
This is to ensure that automated code scanning and license management tools (increasingly popular at SAS and elsewhere) will properly locate the copyright notices.

> [!NOTE]
> Source code refers to any executable code such as .java or .go files, shell scripts, etc.
> This includes any JS/CSS files that you might be serving out to browsers.
> It does not refer to content such as documentation, build scripts, or configuration files.

The following header template contains the minimum requirements:

```
Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
```

### Scrub the history
If you developed your project internally, you may need to scrub its Git history.
Review the project history to ensure no sensitive data are leaked on deployment.
Because scrubbing an extensive Git history can be onerous and time-consuming, the OSPO recommends launching public open source projects with "clean" (blank) Git histories.
However, in cases where maintainers and project team wish to retain Git histories, please be sure to remove the following:

- Names and addresses of employees (unless they give explicit permission)
- References to code names, internal paths or filenames, and internal hosts (e.g., `gitlab.sas.com`, `docker.sas.com`, `registry.unx.sas.com`) or IP addresses
- References to internal Git repositories (e.g., `sas-institute-rnd-internal/xxx`)
- References to internal group names (e.g., `@sas-institute-rnd-product/xxx`)

### Remove unnecessary files
When you have completed your work, delete the `INSTRUCTIONS.md` file from your repository.
Additionally, if you have not used the kit's documentation materials, remove the following components from the repository:

- the `website` directory and all files that it contains
- the `Update Documentation` section of the `CONTRIBUTING.md` file
- `.github/dependabot.yml`
- `.github/workflows/deploy-doc.yml`

### Review the Final Preparation Checklist
The Open Source Program Office uses the following checklist to ensure are first-party open source projects are ready for public release.
By reviewing the checklist and ensuring your project's alignment with, you help expedite approval of your Open Source Contributions request.

- [ ] Properly formatted README.md file is present
- [ ] Properly formatted SUPPORT.md file is present
- [ ] Properly formatted CONTRIBUTING.md file is present
- [ ] Properly formatted SECURITY.md file is present if necessary
- [ ] Copy of SAS Contributor Agreement is present if necessary
- [ ] LICENSE file matches approved license
- [ ] Source code files contain required headers
- [ ] INSTRUCTIONS.md file is removed
- [ ] Comment blocks in template files are removed
- [ ] website directory is removed if not in use
- [ ] dependabot.yml file is removed from .github folder if not in use
- [ ] deploy-doc.yml file is removed from .github/workflows if not in use
- [ ] Git history has been scrubbed if necessary
- [ ] Remaining guidance from Legal has been addressed
