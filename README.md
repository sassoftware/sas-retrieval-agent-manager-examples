# sas-retrieval-agent-manager-examples

## Overview

test
This repository contains code examples for using the APIs provided by SAS Retrieval Agent Manager.

<!--
### What's New
If applicable to your project, list new features you want users to be aware of.
This section might supplement the Changelog file from the repository and only highlight important changes.
-->

### Examples

| Example | Description |
| ------ | ------ |
| [chat web app](/chat-webapp/) | This example demonstrates how to build a web-based chat interface to interact with SAS Retrieval Agent Manager (RAM). The application allows users to authenticate with their SAS RAM credentials, select from available document collections, and ask questions about private documents that have been added to SAS RAM Agent Manager. It provides a complete implementation of a Next.js-based chat application with authentication, session management, and real-time query capabilities. |
| [banking agent](/examples/agents/banking_agent/) | Banking climate-risk analysis agent that queries bank report collections, supports templated questions, compares bank groups, and can generate chart output. |
| [doc metadata augmentation agent](/examples/agents/doc_metadata_augmentation_agent/) | Demonstrates retrieval with metadata-aware prompting by injecting file name, page number, and chunk details into LLM context. |
| [financial agent](/examples/agents/financial_agent/) | This example demonstrates a RAM agent that combines structured financial data queries with unstructured document search to generate client-specific daily market updates. |
| [image render agent](/examples/agents/image_render_agent/) | Demonstrates how to render tool-generated images in RAM chat using base64-encoded image output. |
| [multiple llms agent](/examples/agents/multiple_llms_agent/) | Routes prompts between low- and high-reasoning LLM aliases to show dynamic multi-model selection in a single agent template. |
| [news search tools](/examples/code_mcp_servers/news_search_tools/) | A Code MCP server providing web search tools (DuckDuckGo, Reddit, NYT, Yahoo Finance) used by the news agent examples. |
| [news custom source](/examples/custom_sources/news_source/) | A custom source template that fetches daily news from NYT, Reddit, and Yahoo Finance for a configurable news domain. |
| [NYT front page source](/examples/custom_sources/nyt_front_page_source/) | A custom source template that fetches daily headlines from all 26 NYT Top Stories sections. |
| [business news agent](/examples/agents/business_news_agent/) | A no-code agent specialized in business and financial news, with access to a news collection and search tools. |
| [health news agent](/examples/agents/health_news_agent/) | A no-code agent specialized in health and medical news, with access to a news collection and search tools. |
| [science and tech news agent](/examples/agents/science_tech_news_agent/) | A no-code agent specialized in science and technology news, with access to a news collection and search tools. |
| [news information finder](/examples/agents/news_information_finder/) | A general-purpose news search agent with access to all news collections and web search tools. |
| [simple orchestrator](/examples/agent_orchestrators/simple_orchestrator/) | A minimal no-code orchestrator example that demonstrates the basic sub-agent coordination pattern. |
| [news orchestrator](/examples/agent_orchestrators/news_orchestrator/) | An advanced orchestrator that coordinates domain-specific news agents to produce cross-domain news analysis and insight-driven narratives. |

## Contributing

Maintainers are accepting patches and contributions to this project.
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details about submitting contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

[SAS Retrieval Agent Manager Help Center](https://go.documentation.sas.com/doc/en/ragntmgrcdc/default/ragntmgrug/titlepage.htm)
