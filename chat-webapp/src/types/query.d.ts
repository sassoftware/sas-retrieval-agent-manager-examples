export interface Query {
    id: string;
    content: QueryContent;
    update_timestamp: string;
    response?: {
        answer?: string;
    }
    querySessionId: string;
    errors_text?: string;
    parentQueryId?: string | null;
    origin?: string;
}



export interface QueryRequest {
    querySessionId?: string;
    content: QueryContent;
    collectionIds?: string[];
    agentId?: string;
}

export interface QueryTextContent {
    role: "user";
    content: Array<{
        type: "text";
        text: string;
    } | QueryImageContent | QueryFileContent>;
}

export interface QueryImageContent {
    type: "image";
    mime_type: "image/png" | "image/jpeg" | "image/webp" | "image/gif";
    base64: string;
    extras: {
        name: string;
        size_bytes: number;
    };
}

export interface QueryFileContent {
    type: "file";
    mime_type: "application/pdf" | "text/plain" | "text/markdown" | "text/csv" | "application/json";
    base64: string;
    extras: {
        name: string;
        size_bytes: number;
    };
}

export type QueryContent = string | QueryTextContent[];
