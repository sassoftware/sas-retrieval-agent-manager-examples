from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import base64
from io import BytesIO
import re

import matplotlib.pyplot as plt

from sasram.agent import Client


# Alias definitions
ALIAS_ALL = "ALL"
ALIAS_ABN = "ABN"
ALIAS_BBVA = "BBVA"
ALIAS_LBP = "LBP"
ALIAS_DEU = "Deutsche"
ALIAS_DNB = "DNB"
ALIAS_ING = "ING"
ALIAS_INTESA = "Intesa Sanpaolo"
ALIAS_NORD = "Nordea"
ALIAS_RBI = "RBI"
ALIAS_UNI = "UniCredit"
ALL_ALIASES = [
    ALIAS_ABN,
    ALIAS_BBVA,
    ALIAS_LBP,
    ALIAS_DEU,
    ALIAS_DNB,
    ALIAS_ING,
    ALIAS_INTESA,
    ALIAS_NORD,
    ALIAS_RBI,
    ALIAS_UNI
]


# Mapping of bank sizes to invididual banks
BANK_CLASSIFICATIONS = {
    "large": [ALIAS_DEU, ALIAS_UNI, ALIAS_INTESA, ALIAS_ING, ALIAS_NORD],
    "medium": [ALIAS_BBVA, ALIAS_ABN, ALIAS_RBI],
    "small": [ALIAS_DNB, ALIAS_LBP],
}

@dataclass
class QuestionTemplate:
    question: str
    answer_choices: str

questions = [
    QuestionTemplate(
        question="With respect to environmental, social and governance (ESG), which data sources were used in the analysis of climate-related physical risk?",
        answer_choices="""
    External data providers
    Public open-source data portals
    Government or regulatory databases
    Counterparties questionnaires
    Company disclosures (financial reports, sustainability reports)
    Internal data
    Industry benchmarks
    Scientific literature and climate models"""
    ),
    QuestionTemplate(
        question="With respect to environmental, social and governance (ESG), what is the granularity level of the analysis of climate-related physical risk?",
        answer_choices="""
    Country level
    District level (NUTS 3)
    Latitude/longitude level
    Address data
    Postal/zip code"""
    ),
    QuestionTemplate(
        question="With respect to environmental, social and governance (ESG), what time horizon is considered in the analysis of climate-related physical risk?",
        answer_choices="""
    Short term
    Medium term
    Long term"""
    ),
]

questions_str = ""
for idx, q in enumerate(questions):
    questions_str += f"    - {idx}: {q.question}\n"


HELP_TEXT = f"""
# Welcome to the RAM Banking ESG demo! 

## Available commands:
  - To ask a specific question from the template, type the index of the question you would like to ask followed by the company: {ALL_ALIASES} or 'ALL'. Template questions:\n
{questions_str}
  - `#table`: Ask specifically about the ING Pillar3Report table. `#table: What are the highest sectors by value?`
  - `#plot`: Generate a bar chart from the pillar report. Ex: `#plot: column b (Gross carrying amount)`
  - `#compare`: Compare groups of banks. Available groups are: 'large', 'medium', 'small' or any invidual bank. Ex: `#compare: large, small, physical risk`
  - Or, feel free to ask any question about the source docs.
"""
INIT_CMD = "#HELP"


def exec(text: str, client, options: dict[str, Any]):
    # instructions
    if text == INIT_CMD:
        return HELP_TEXT

    try:
        question_idx, collection = text.split(",")
        question_idx = int(question_idx)
        if collection not in (ALL_ALIASES + ["ALL"]):
            return f"Collection alias not recognized. Select one of ALL or {ALL_ALIASES}"

        if collection == "ALL":
            all_answers = ""
            # Ask questions one collection at a time
            for b in ALL_ALIASES:
                all_answers += f"\r\n## {b}\r\n"
                all_answers += answer_question(client, question_idx, b)
            return all_answers
        else:
            return answer_question(client, question_idx, collection)
    except ValueError:
        pass

    table = """<table><tbody><tr><th colspan="15">Template 5: Banking book - Climate change physical risk: Exposures subject to physical risk</th></tr><tr><th>a</th><th>b</th><th>c</th><th>d</th><th>e</th><th>f</th><th>g</th><th>h</th><th>i</th><th>j</th><th>k</th><th>l</th><th>m</th><th>n</th><th>o</th></tr><tr><th rowspan="4">Consolidated</th><th></th><th colspan="13">Gross carrying amount (Mln EUR)</th></tr><tr><th rowspan="2"></th><th colspan="10">of which exposures sensitive to impact from climate change physical events</th><th colspan="3"></th></tr><tr><th colspan="5">Breakdown by maturity bucket</th><th rowspan="2">of which exposures sensitive to impact from chronic climate change events</th><th rowspan="2">of which exposures sensitive to impact from acute climate change events</th><th rowspan="2">of which exposures sensitive to impact both from chronic and acute climate change events</th><th rowspan="2">Of which Stage 2 exposures</th><th rowspan="2">Of which non- performing exposures</th><th>Accumulated negative changes risk and provisions</th><th colspan="2">impairment, accumulated in fair value due to credit</th></tr><tr><th></th><th>&lt;= 5 years</th><th>&gt; 5 year &lt;= 10 years</th><th>&gt; 10 year &lt;= 20 years</th><th>&gt; 20 years</th><th>Average weighted maturity</th><th></th><th>of which Stage 2 exposures</th><th>Of which non- performing exposures</th></tr><tr><td>1 A - Agriculture, forestry and fishing</td><td>3,161</td><td>375</td><td>350</td><td>74</td><td>6</td><td>4</td><td>662</td><td>87</td><td>57</td><td>69</td><td>3</td><td>-5</td><td>-1</td><td>-3</td></tr><tr><td>2 B - Mining and quarrying</td><td>7,504</td><td>646</td><td>332</td><td>368</td><td></td><td>2</td><td>347</td><td>52</td><td>947</td><td>200</td><td>41</td><td>-27</td><td>-1</td><td>-25</td></tr><tr><td>3 C - Manufacturing</td><td>47,791</td><td>5,009</td><td>1,401</td><td>672</td><td>17</td><td>2</td><td>5,025</td><td>183</td><td>1,890</td><td>814</td><td>74</td><td>-118</td><td>-14</td><td>-97</td></tr><tr><td>4 D - Electricity, gas, steam and air conditioning supply</td><td>19,888</td><td>1,720</td><td>1,622</td><td>2,734</td><td>228</td><td>5</td><td>2,799</td><td>53</td><td>3,452</td><td>532</td><td>97</td><td>-41</td><td>-4</td><td>-35</td></tr><tr><td>E - Water supply; sewerage, 5 waste management and remediation activities</td><td>2,867</td><td>51</td><td>15</td><td>18</td><td></td><td>1</td><td>3</td><td>10</td><td>72</td><td>21</td><td>4</td><td>-4</td><td></td><td>-4</td></tr><tr><td>6 F - Construction</td><td>10,025</td><td>3,048</td><td>822</td><td>660</td><td>9</td><td>3</td><td>4,045</td><td>121</td><td>374</td><td>477</td><td>15</td><td>-98</td><td>-9</td><td>-84</td></tr><tr><td>G - Wholesale and retail 7 trade; repair of motor vehicles and motorcycles</td><td>35,837</td><td>2,714</td><td>688</td><td>338</td><td>8</td><td>2</td><td>2,311</td><td>484</td><td>953</td><td>473</td><td>37</td><td>-73</td><td>-8</td><td>-60</td></tr><tr><td>8 H - Transportation and storage</td><td>25,148</td><td>1,630</td><td>1,188</td><td>540</td><td>1</td><td>3</td><td>1,409</td><td>526</td><td>1,425</td><td>170</td><td>18</td><td>-21</td><td>-2</td><td>-18</td></tr><tr><td>9 I - Accommodation and food service activities</td><td>2,201</td><td>105</td><td>43</td><td>11</td><td></td><td>4</td><td>42</td><td>56</td><td>62</td><td>24</td><td>10</td><td>-5</td><td></td><td>-5</td></tr><tr><td>10 J - Information and communication</td><td>16,915</td><td>548</td><td>221</td><td>96</td><td>1</td><td>2</td><td>520</td><td>125</td><td>220</td><td>80</td><td>7</td><td>-14</td><td>-1</td><td>-12</td></tr><tr><td>11 M - Professional, scientific and technical activities</td><td>6,714</td><td>999</td><td>663</td><td>747</td><td>46</td><td>5</td><td>2,368</td><td>58</td><td>29</td><td>227</td><td>10</td><td>-30</td><td>-6</td><td>-21</td></tr><tr><td>12 N - Administrative and support service activities</td><td>13,364</td><td>1,019</td><td>440</td><td>166</td><td>1</td><td>2</td><td>1,371</td><td>176</td><td>79</td><td>150</td><td>5</td><td>-32</td><td>-2</td><td>-28</td></tr><tr><td>O - Public administration and 13 defence; compulsory social security</td><td>1,803</td><td>104</td><td>119</td><td>761</td><td>72</td><td>9</td><td>1,048</td><td>1</td><td>7</td><td></td><td></td><td></td><td></td><td></td></tr><tr><td>14 P - Education</td><td>239</td><td>22</td><td>18</td><td>50</td><td>1</td><td>5</td><td>83</td><td>7</td><td>1</td><td>3</td><td></td><td>-1</td><td></td><td></td></tr></tbody></table>"""
    if text.startswith("#plot"):
        try:
            vals = text.split(":")
            if len(vals) != 2:
                return "Error parsing arguments. Usage: '#plot: <column to plot>"
            category = vals[1]
        except Exception as e:
            return e

        img, labels = generate_plot(client, category, table)
        return f"![graph](data:image/png;base64,{img})"
    elif text.startswith("#table"):
        prompt = f"""Answer the user's query about information in this table
        Query:
        {text}
        Table:
        {table}
        """
        response = client.post_query(
            prompt=prompt,
            direct_llm_query=True,
        )
        return response.response.answer
    elif text.startswith("#compare"):
        try:
            _, cmd_args = text.split(":")
        except Exception as e:
            return e
        try:
            group_one, group_two, search_term = cmd_args.split(",")
        except Exception as e:
            return e

        return run_comparison(client, group_one.strip(), group_two.strip(), search_term)

    # Else just process as a regular query on these docs
    response = client.post_query(text)

    return response.response.answer


def answer_question(client, question_idx, collection_name="default"):
    question = questions[question_idx].question
    answer_choices = questions[question_idx].answer_choices

    docs = client.retrieve_docs(
        prompt=question + " " + answer_choices,
        collection_name=collection_name,
        search_kwargs={
            "k": 15,
        }
    )

    context_str = "\n"
    for idx, d in enumerate(docs):
        context_str += f"Chunk: {idx}\n"
        context_str += f"Document: {Path(d.metadata['source']).name}\n"
        context_str += f"Page number: {d.metadata['page_number']}\n"
        context_str += f"Text: {d.page_content}\n\n"

    prompt = f"""Use the following context to answer the user's question.

    Question: {question}
    For your answer, select from one or more of the following choices:
    {answer_choices}

    Context: {context_str}

    Format your answer as a markdown table with columns for
    'Selected Answer', 'Context', 'Document', and 'Page Number',
    where each row is one of your answer choices.
    """

    response = client.post_query(prompt, direct_llm_query=True)
    return f"Question: {question}\n\n" + response.response.answer


def generate_plot(client, column_name, table):
    prompt = f"""Please extract the {column_name} column for each sector
    using the following table:
    {table}

    Example response (inserting a newline between each sector):
      A - Agriculture, forestry and fishing: <value>
      B - Mining and quarrying: <value>
      C - Manufacturing: <value>
      <continue for all categories>
    """
    response = client.post_query(
        prompt=prompt,
        direct_llm_query=True
    )
    data_str = response.response.answer

    print(data_str)

    sectors = {}
    for line in data_str.splitlines():
        if ":" in line:
            try:
                label, value = line.split(":", 1)  # split at the first colon only
                sectors[label.strip()] = int(value.strip().replace(",", ""))
            except Exception:
                continue

    print(sectors)

    labels_full = list(sectors.keys())
    values = list(sectors.values())

    # Extract just the leading letters (before the " - ")
    labels_short = [lbl.split(" - ")[0] for lbl in labels_full]

    # --- Bar Chart ---
    #plt.figure(figsize=(12, 6))
    bars = plt.bar(labels_short, values)
    plt.xlabel("Sector")
    plt.title(column_name)
    #plt.xticks(rotation=75, ha="right")  # rotate labels so they don’t overlap

    #plt.tight_layout()
    plt.ylabel("Value")

    # Add legend mapping short labels to full names
    legend_labels = [f"{short}: {full}" for short, full in zip(labels_short, labels_full)]
    #plt.legend(bars, legend_labels, title="Sectors", bbox_to_anchor=(1.05, 1), loc="upper left")

    buffer = BytesIO()
    plt.savefig(buffer, format="png")
    plt.close()
    buffer.seek(0)

    # Encode to base64
    img_base64 = base64.b64encode(buffer.read()).decode('utf-8')
    return img_base64, labels_full


def run_comparison(
    client: Client,
    group_one: str,
    group_two: str,
    search_term: str,
    top_k: int = 15,
) -> str:
    """
    Generates a comparison report between two groups of banks.
    """
    print("group 1:", group_one)
    print("group 2:", group_two)
    print("search:", search_term)

    # Step 1. Use the search term to retrieve the context for each group
    group_one_docs = retrieve_context_for_group(client, group_one, search_term, top_k)
    group_two_docs = retrieve_context_for_group(client, group_two, search_term, top_k)

    # Step 2. Prompt LLM to compare each bank
    prompt = f"""The user would like to compare and contrast the information
related to '{search_term}' between two groups of banks. Here is the relevant
context for each bank group.

Group 1: {group_one}
{group_one_docs}

Group 2: {group_two}
{group_two_docs}

Please use the given context to generate a markdown table comparing the
approach for '{search_term}' for each banking group. Include a column
for the document you based your answer on which says the document name and
page number of the relevant context.
"""
    response = client.post_query(
        prompt=prompt,
        direct_llm_query=True,
    )
    return response.response.answer


def retrieve_context_for_group(client: Client, group_name: str, search_term: str, top_k: int = 15):

    def docs_to_string(docs):
        doc_str = ""
        for idx, d in enumerate(docs):
            doc_str += f"Chunk: {idx}\n"
            doc_str += f"Document: {Path(d.metadata['source']).name}\n"
            doc_str += f"Page number: {d.metadata['page_number']}\n"
            doc_str += f"Text: {d.page_content}\n\n"
        return doc_str

    context_str = ""
    # Validate groups
    if group_name in ["large", "medium", "small"]:
        # Reference in a cluster of banks, so retrieve docs for each individually
        banks_in_group = BANK_CLASSIFICATIONS[group_name]

        context_str += f"{'*' * 80}\n{group_name} - Banks: {banks_in_group}"
        for bank in banks_in_group:
            context_str += f"{'*' * 40}\n{bank} chunks\n"
            docs = client.retrieve_docs(
                prompt=search_term,
                collection_name=bank,
                search_kwargs={"k": top_k}
            )
            context_str += docs_to_string(docs)
    elif group_name in ALL_ALIASES:
        context_str += f"{'*' * 80}\n{group_name} chunks\n"

        # Reference just a single bank
        docs = client.retrieve_docs(
            prompt=search_term,
            collection_name=group_name,
            search_kwargs={"k": top_k}
        )
        context_str += docs_to_string(docs)
    else:
        raise ValueError("Unexpected group name")

    return context_str