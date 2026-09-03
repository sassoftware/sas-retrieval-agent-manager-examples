# SAS Retrieval Agent Manager Chat Application Example

## Overview

This example demonstrates how to build a web-based chat interface to interact with SAS Retrieval Agent Manager (RAM). The application allows users to authenticate with their SAS RAM credentials, select from available document collections, and ask questions about private documents that have been added to SAS RAM Agent Manager. It provides a complete implementation of a Next.js-based chat application with authentication, session management, and real-time query capabilities.

## Use Case

Organizations need to provide employees with the ability to ask questions about internal documentation, knowledge bases, or private document repositories. This example demonstrates how to build a user-friendly chat interface that connects to SAS Retrieval Agent Manager and enables users to do the following tasks:

- Authenticate using your SAS Retrieval Agent Manager credentials (via SSO or device code)
- Browse available document collections
- Create and continue chat sessions
- Submit queries and receive AI-generated responses based on private documents
- View conversation history across multiple sessions

## Prerequisites

Before running this example, make sure you have the following prerequisites:

- Access to a running SAS Retrieval Agent Manager instance
- Your user login credentials for the SAS Retrieval Agent Manager instance
- Document collections created by or accessible to your SAS Retrieval Agent Manager user account
- Docker or Node.js v20 installed on your system

## Technologies Used

This example web application is built using React v19, Next.js v15, Redux v2.9 and Material UI components v7.3.2.  See [third party libraries](./THIRDPARTY.md) for a complete list of the libraries used and links to their respective licenses.

### Application Structure

The following list describes the main components of the application:

- [Login Page](src/app/LoginPage.tsx): This component handles user authentication using SSO (OIDC authorization code flow with PKCE) or the OAuth 2.0 device code flow with PKCE.
- [Chat Page](src/app/chat/page.tsx): This component lists collections and enables users to select a document collection to query.
- [Chat Collection Page](src/app/chat/[collectionId]/page.tsx): This component allows users to choose which collection of documents to query.
- [Questions Page](src/app/chat/[collectionId]/[sessionId]/page.tsx): This component has a chat interface where users can ask questions and view responses.
- [Authentication](src/services/auth.ts): This component provides an authentication service that manages device-code token retrieval and refresh.
- [SSO Service](src/services/sso.ts): This component handles the SSO authorization code flow with PKCE, including token exchange, refresh, and RP-initiated logout.
- [Chat Service](src/services/chat.ts): This component has a chat service that handles API calls for collections, sessions, and queries.
- [TypeScript Definitions (Collection Objects)](src/types/collection.d.ts): This component contains TypeScript definitions for collection objects.
- [TypeScript Definitions (Query Sessions)](src/types/query-session.d.ts): This component contains TypeScript definitions for query sessions.

## Installation and Setup

### Configuration

1. Create a `.env` file in the website directory based on the `.env.example` file by running the following command:

```bash
cp .env.example .env
```

2. Update the `.env` file with your SAS Retrieval Agent Manager configuration:

```
# Base URL for your SAS Retrieval Agent Manager instance
RAM_URL=https://<your host here>
```

**NOTE:** Replace `<your host here>` with the host name of your SAS Retrieval Agent Manager deployment (for example, `https://ram-server.example.com`).

#### Optional: Single Sign-On (SSO)

By default, users sign in with the OAuth 2.0 device code flow (no additional configuration required). To also offer a "Sign in" button that redirects users through your identity provider (Keycloak) using the OIDC authorization code flow with PKCE, add the following to your `.env` file:

```
KEYCLOAK_CLIENT_ID=sas-ram-api
KEYCLOAK_CLIENT_SECRET=
KEYCLOAK_REDIRECT_URI=http://localhost:3000/auth/callback
KEYCLOAK_POST_LOGOUT_REDIRECT_URI=http://localhost:3000/
KEYCLOAK_SESSION_SECRET=replace-with-a-long-random-secret
```

- `KEYCLOAK_REDIRECT_URI` and `KEYCLOAK_POST_LOGOUT_REDIRECT_URI` must be registered as valid redirect/post-logout URIs on the Keycloak client, and must use the externally-reachable hostname users will access the app through.
- `KEYCLOAK_SESSION_SECRET` should be a long random value.
- If the app is served under `NEXT_PUBLIC_BASE_PATH` (for example `/ChatExtension`), the redirect and post-logout URIs are automatically normalized to include that prefix.
- SSO sessions are stored in an in-memory server-side store. This works for a single application instance; a multi-replica deployment would need a shared store (for example Redis) instead.
- The device-code flow remains available even when SSO is configured.

1. Build the Docker image from the website directory by running the following command:

```bash
docker build -t chat-app .
```

2. Run the container by running the following command:

```bash
docker run -it --rm -p 3000:3000 --env-file .env chat-app
```

3. Open your browser and navigate to `http://localhost:3000`. You should see a login page with **Sign in** and **Sign in with device code** buttons.

4. If SSO is configured, click **Sign in** to be redirected to your identity provider's login page, then redirected back to the application once authenticated.

5. To use the device code flow instead, click **Sign in with device code**. A page then opens with the following information:

   - A user code
   - A verification URL

6. Click the **COPY** button next to the user code.

7. Click the **Verification URL** link and a new tab opens in your browser.

8. Paste the user code in the **Device Login** field and click **Submit**.

9. Click **Yes** when prompted **"Do you grant these access privileges?"**.

### Running with Node.js

1. Install dependencies by running the following command:

```bas
npm install
```

2. Start the development server by running the following command:

```bash
npm run dev
```

> If you're testing locally with `NEXT_PUBLIC_BASE_PATH` set (for example `/ChatExtension`), use `npm run dev:basepath` instead. Plain `next dev` (`npm run dev`) doesn't apply the base-path rewriting that the production Docker image gets from `server.js`, so pages/cookies/redirects under a base path won't resolve correctly with it. `dev:basepath` runs the same `server.js` used in production, just in Next's dev mode.

1. Open your browser and navigate to `http://localhost:3000` and follow the device code authentication flow as described in the preceeding Docker instructions.

## Using the Application

After successfully logging in to the example web application, the **Collections** page displays all of your available document collections from SAS Retrieval Agent Manager. On the **Collections** page, do any of the following:

- Select a collection by clicking its name.
- Start a new chat session by clicking the **START NEW CHAT** button.
- Continue a previous conversation by clicking <img src="img/3-line-menu-icon.png" alt="3 line menu" style="width: 17px; height: 19px;"> and selecting the initial prompt text.

When the chat interface appears, enter your question or response into the text field, and click <img src="img/send-icon.png" alt="send" style="width: 17px; height: 19px;">.
An AI-generated response appears based on the documents in the selected collection. All queries and responses are saved to the session for future reference.

To sign out, click the sign-out icon in the top navigation bar. This clears the current session (SSO or device code) and returns you to the login page.

## Troubleshooting

In the event that an error occurs, detailed technical error information is logged where you executed `docker run` or `npm run`.

### "No Collections Available" on the Collections Page

- Verify that the `RAM_URL` in your `.env` file is correct.
- Verify that collections have been created in SAS Retrieval Agent Manager.
- Ensure that your user account has permission to access collections.
- Check the browser console for any API errors.

### "Failed to send message" on the Chat Page

- Check the technical error information logged.
- Check the **Network** tab in the browser's developer tools.
- Perform the same query using the SAS RAW web UI.
- If the problem persists and is unique to the example web application, submit a GitHub issue or contact SAS Support via the [SAS Retrieval Agent Manager Learn and Support Page](https://support.sas.com/en/software/retrieval-agent-manager-support.html).

### "Single sign-on failed" Message on the Login Page

- Verify `KEYCLOAK_REDIRECT_URI` and `KEYCLOAK_POST_LOGOUT_REDIRECT_URI` are registered as valid redirect/post-logout URIs on the Keycloak client.
- Verify `RAM_URL`, `KEYCLOAK_CLIENT_ID`, and `KEYCLOAK_SESSION_SECRET` are all set correctly.
- Check the server log for a message starting with `SSO callback failed:` for the underlying error.