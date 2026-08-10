# sas-retrieval-agent-manager-examples

## Overview

This repository contains code examples for using the APIs provided by SAS Retrieval Agent Manager (RAM).

<!--
### What's New
If applicable to your project, list new features you want users to be aware of.
This section might supplement the Changelog file from the repository and only highlight important changes.
-->

### Examples

#### Web App

| Example | Description |
| ------ | ------ |
| [chat web app](/chat-webapp/) | This example demonstrates how to build a web-based chat interface to interact with SAS Retrieval Agent Manager. The application allows users to authenticate with their SAS RAM credentials, select from available document collections, and ask questions about private documents that have been added to SAS RAM Agent Manager. It provides a complete implementation of a Next.js-based chat application with authentication, session management, and real-time query capabilities. |

#### Agent Orchestrators

| Example | Description |
| ------ | ------ |
| [news orchestrator](/examples/agent_orchestrators/news_orchestrator/) | An advanced orchestrator that coordinates domain-specific news agents to produce cross-domain news analysis and insight-driven narratives. |
| [simple orchestrator](/examples/agent_orchestrators/simple_orchestrator/) | A minimal, no-code orchestrator example that demonstrates the basic sub-agent coordination pattern. |

#### Agents

| Example | Description |
| ------ | ------ |
| [banking agent](/examples/agents/banking_agent/) | A banking climate-risk analysis agent that queries bank report collections, supports templated questions, compares bank groups, and can generate chart output. |
| [business news agent](/examples/agents/business_news_agent/) | A no-code agent specialized in business and financial news, with access to a news collection and search tools. |
| [default tool calling agent](/examples/agents/default_tool_calling_agent/) | A default RAM code agent template that uses experiment-configured tools, collections, and retrieval settings. |
| [doc metadata augmentation agent](/examples/agents/doc_metadata_augmentation_agent/) | An agent that demonstrates retrieval with metadata-aware prompting by injecting file name, page number, and chunk details into LLM context. |
| [financial agent](/examples/agents/financial_agent/) | An agent that combines structured financial data queries with unstructured document search to generate client-specific daily market updates. |
| [health news agent](/examples/agents/health_news_agent/) | A no-code agent specialized in health and medical news, with access to a news collection and search tools. |
| [image render agent](/examples/agents/image_render_agent/) | An agent that demonstrates how to render tool-generated images in the RAM chat using base64-encoded image output. |
| [multiple llms agent](/examples/agents/multiple_llms_agent/) | An agent that routes prompts between low- and high-reasoning LLM aliases to show dynamic multi-model selection in a single agent template. |
| [news information finder](/examples/agents/news_information_finder/) | A general-purpose news search agent with access to all news collections and web search tools. |
| [science and tech news agent](/examples/agents/science_tech_news_agent/) | A no-code agent specialized in science and technology news, with access to a news collection and search tools. |

#### Code MCP Servers

| Example | Description |
| ------ | ------ |
| [finance tools](/examples/code_mcp_servers/finance_tools/) | An MCP server example that has finance and quantitative analysis tools, including market data lookup, regression, summary statistics, and arithmetic helpers. |
| [news search tools](/examples/code_mcp_servers/news_search_tools/) | An MCP server example that has web search tools for finding news from NYT, Reddit, DuckDuckGo, and Yahoo Finance. |
| [simple calculator](/examples/code_mcp_servers/simple_calculator/) | A minimal single-tool MCP server example that adds two integers. |
| [web search](/examples/code_mcp_servers/web_search/) | A lightweight web search MCP server example built on DuckDuckGo search via the `ddgs` package. |

#### Container MCP Servers

| Example | Description |
| ------ | ------ |
| [chart generator](/examples/container_mcp_servers/chart_generator/) | A container MCP server that generates charts and returns base64-encoded images for use in RAM agents. |
| [Postgres db connection template](/examples/container_mcp_servers/postgres_db_connection_template/) | A container MCP server template that uses Google GenAI Toolbox prebuilt Postgres tools for database connectivity. |
| [SAS Viya connection](/examples/container_mcp_servers/sas_mcp_server/) | A container MCP server template that uses sassoftware/sas-mcp-server tools for connectivity with SAS Viya. |

#### Custom Sources

| Example | Description |
| ------ | ------ |
| [financial news fetcher](/examples/custom_sources/financial_news_fetcher/) | A custom source example that fetches technology-sector financial news, generates a PDF digest, and saves the PDF into a RAM source for downstream collection ingestion. |
| [news source](/examples/custom_sources/news_source/) | A parameterized news source that fetches from NYT, Reddit, and Yahoo Finance for a configurable news domain. |
| [NYT front page source](/examples/custom_sources/nyt_front_page_source/) | A custom soure example that fetches the daily headlines from all 26 NYT Top Stories sections. |

## Contributing

Maintainers are accepting patches and contributions to this project.
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details about submitting contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

[SAS Retrieval Agent Manager Help Center](https://go.documentation.sas.com/doc/en/ragntmgrcdc/default/ragntmgrug/titlepage.htm)
