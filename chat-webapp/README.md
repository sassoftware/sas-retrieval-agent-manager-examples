# SAS Retrieval Agent Manager Chat Application Example

## Overview

This example demonstrates how to build a web-based chat interface to interact with SAS Retrieval Agent Manager (RAM). The application allows users to authenticate with their SAS RAM credentials, select from available document collections, and ask questions about private documents that have been added to SAS RAM Agent Manager. It provides a complete implementation of a Next.js-based chat application with authentication, session management, and real-time query capabilities.

## Use Case

Organizations need to provide employees with the ability to ask questions about internal documentation, knowledge bases, or private document repositories. This example demonstrates how to build a user-friendly chat interface that connects to SAS Retrieval Agent Manager and enables users to do the following:

- Authenticate using your SAS Retrieval Agent Manager credentials
- Browse available document collections
- Create and continue chat sessions
- Submit queries and receive AI-generated responses based on private documents
- View conversation history across multiple sessions

## Prerequisites

Before running this example, make sure you have the following:

- Access to a running SAS Retrieval Agent Manager instance
- Your user login credentials for the SAS Retrieval Agent Manager instance
- Document collections created by or accessible to your SAS Retrieval Agent Manager user account
- Docker or Node.js v20 installed on your system

## Technologies Used

This example web application is built using React v19, Next.js v15, Redux v2.9 and Material UI components v7.3.2.

### Application Structure

The following list describes the main components of the application:

- [Login Page](src/app/LoginPage.tsx): This component handles user authentication using OAuth 2.0 device code flow with PKCE.
- [Chat Page](src/app/chat/page.tsx): This component lists collections and enables users to select a document collection to query.
- [Chat Collection Page](src/app/chat/[collectionId]/page.tsx): This component allows users to choose which collection of documents to query.
- [Questions Page](src/app/chat/[collectionId]/[sessionId]/page.tsx): This component has a chat interface where users can ask questions and view responses.
- [Authentication](src/services/auth.ts): This component provides an authentication service that manages token retrieval and token refresh.
- [Chat Service](src/services/chat.ts): This component has a chat service that handles API calls for collections, sessions, and queries.
- [TypeScript Definitions (Collection Objects)](src/types/collection.d.ts): This component contains TypeScript definitions for collection objects.
- [TypeScript Definitions (Query Sessions)](src/types/query-session.d.ts): This component contains TypeScript definitions for query sessions.

## Installation and Setup

### Configuration

1. Create a `.env` file in the website directory based on the `.env.example` file by using the following command:

```bash
cp .env.example .env
```

2. Update the `.env` file with your SAS Retrieval Agent Manager configuration:

```
# Base URL for your SAS Retrieval Agent Manager instance
RAM_URL=https://<your host here>
```

**NOTE:** Replace `<your host here>` with the host name of your SAS Retrieval Agent Manager deployment (e.g., `https://ram-server.example.com`).

1. Build the Docker image from the website directory by using the following command:

```bash
docker build -t chat-app .
```

2. Run the container by using the following command:

```bash
docker run -it --rm -p 3000:3000 --env-file .env chat-app
```

3. Open your browser and navigate to `http://localhost:3000`. You should see a login page with a **Sign In with Device Code** button.

4. Click the sign in button to initiate authentication. You'll then see a page wtih the following:

   - A user code
   - A verification URL

5. Click the COPY button next to the user code.

6. Clck on the Verification URL link and a new tab will open in your browser.

7. Paste the user code in the Device Login field and and click Submit.

8. Click Yes to the "Do you grant these access privileges?" prompt.

### Running with Node.js

1. Install dependencies by using the following command:

```bas
npm install
```

2. Start the development server by using the following command:

```bash
npm run dev
```

3. Open your browser and navigate to `http://localhost:3000` and follow the device code authentication flow as described in the Docker instructions above.

## Using the Application

After successfully logging in to the example web application, the collections page displays all your available document collections from SAS Retrieval Agent Manager. On the collections page, do any of the following:

- Select a collection by clicking on its name.
- Start a new chat session by clicking the **START NEW CHAT** button.
- Continue a previous conversation by clicking <img src="img/3-line-menu-icon.png" alt="3 line menu" style="width: 17px; height: 19px;"> and selecting the initial prompt text.

When the chat interface appears, enter your question or response into the text field, and click <img src="img/send-icon.png" alt="send" style="width: 17px; height: 19px;">.
An AI-generated response appears based on the documents in the selected collection. All queries and responses are saved to the session for future reference.

## Troubleshooting

In the event that an error occurs, detailed technical error information is logged where you executed `docker run` or `npm run`.

### "No Collections Available" on the Collections Page

- Verify that the `RAM_URL` in your `.env` file is correct.
- Verify that collections have been created in SAS Retrieval Agent Manager.
- Ensure that your user account has permission to access collections.
- Check the browser console for any API errors.

### "Failed to send message" on the Chat Page

- Check the technical error information logged.
- Check the Network tab in the browser's developer tools.
- Perform the same query using the SAS RAW web UI.
- If problem persists and is unique to the example web application, submit a GitHub issue or contact SAS Support via the [SAS Retrieval Agent Manager Learn and Support Page](https://support.sas.com/en/software/retrieval-agent-manager-support.html).

## Contributing

Maintainers are accepting patches and contributions to this project.
Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details about submitting contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

[SAS Retrieval Agent Manager Help Center](https://go.documentation.sas.com/doc/en/ragntmgrcdc/default/ragntmgrug/titlepage.htm)
