# sas-retrieval-agent-manager-examples

## Overview

This repository contains code examples for using the APIs provided by SAS Retrieval Agent Manager.

<!--
### What's New
If applicable to your project, list new features you want users to be aware of.
This section might supplement the Changelog file from the repository and only highlight important changes.
-->

### Examples

#### Web App

| Example | Description |
| ------ | ------ |
| [chat web app](/chat-webapp/) | This example demonstrates how to build a web-based chat interface to interact with SAS Retrieval Agent Manager (RAM). The application allows users to authenticate with their SAS RAM credentials, select from available document collections, and ask questions about private documents that have been added to SAS RAM Agent Manager. It provides a complete implementation of a Next.js-based chat application with authentication, session management, and real-time query capabilities. |

#### Agent Orchestrators

| Example | Description |
| ------ | ------ |
| [agent orchestrators](/examples/agent_orchestrators/) | Folder for agent orchestrator examples and related setup guidance. |

#### Agents

| Example | Description |
| ------ | ------ |
| [agents](/examples/agents/) | Collection of RAM code agent template examples and general setup guidance. |
| [banking agent](/examples/agents/banking_agent/) | Banking climate-risk analysis agent that queries bank report collections, supports templated questions, compares bank groups, and can generate chart output. |
| [default tool calling agent](/examples/agents/default_tool_calling_agent/) | Default RAM code agent template that uses experiment-configured tools, collections, and retrieval settings. |
| [doc metadata augmentation agent](/examples/agents/doc_metadata_augmentation_agent/) | Demonstrates retrieval with metadata-aware prompting by injecting file name, page number, and chunk details into LLM context. |
| [financial agent](/examples/agents/financial_agent/) | RAM agent that combines structured financial data queries with unstructured document search to generate client-specific daily market updates. |
| [image render agent](/examples/agents/image_render_agent/) | Demonstrates how to render tool-generated images in RAM chat using base64-encoded image output. |
| [multiple llms agent](/examples/agents/multiple_llms_agent/) | Routes prompts between low- and high-reasoning LLM aliases to show dynamic multi-model selection in a single agent template. |

#### Code MCP Servers

| Example | Description |
| ------ | ------ |
| [code mcp servers](/examples/code_mcp_servers/) | Collection of Code MCP server templates and generic setup guidance for RAM. |
| [finance tools](/examples/code_mcp_servers/finance_tools/) | Finance and quantitative analysis tools, including market data lookup, regression, summary statistics, and arithmetic helpers. |
| [simple calculator](/examples/code_mcp_servers/simple_calculator/) | Minimal single-tool MCP server example that adds two integers. |
| [web search](/examples/code_mcp_servers/web_search/) | Lightweight web search MCP server example built on DuckDuckGo search via the `ddgs` package. |

#### Container MCP Servers

| Example | Description |
| ------ | ------ |
| [container mcp servers](/examples/container_mcp_servers/) | Folder for container-based MCP server examples and related setup guidance. |

#### Custom Sources

| Example | Description |
| ------ | ------ |
| [custom sources](/examples/custom_sources/) | Folder for custom source examples and related setup guidance. |
| [financial news fetcher](/examples/custom_sources/financial_news_fetcher/) | Custom source example that fetches technology-sector financial news, generates a PDF digest, and saves it into a RAM source for downstream collection ingestion. |

## Contributing

Maintainers are accepting patches and contributions to this project.
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details about submitting contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

[SAS Retrieval Agent Manager Help Center](https://go.documentation.sas.com/doc/en/ragntmgrcdc/default/ragntmgrug/titlepage.htm)
