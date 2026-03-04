
export interface QuerySession {
    id: string;
    title: string;
    insertTimestamp: string;
    updateTimestamp: string;
    metadata?: {
        collection_ids?: string[]
    }
}

export interface ListQuerySessionsResponse {
    items: QuerySession[];
    count: number;
    limit: number;
    name: string;
    start: number;
}


export interface GetQuerySessionResponse {
    items: Query[];
    sessionId: string;
}