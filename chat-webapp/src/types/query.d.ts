export interface Query {
    id: string;
    content: string;
    update_timestamp: string;
    response?: {
        answer?: string;
    }
    querySessionId: string;
    errors_text?: string;
}



export interface QueryRequest {
    querySessionId?: string;
    content: string;
    collectionIds: string[];
}