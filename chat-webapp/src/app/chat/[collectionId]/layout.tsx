'use client';
import { useAppSelector } from "@/store";
import { Box, Drawer, IconButton, List, ListItem, ListItemButton, ListItemText } from "@mui/material";
import MenuIcon from '@mui/icons-material/Menu';
import FirstPage from '@mui/icons-material/FirstPage';
import { use, useMemo, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { useGetAgentsQuery, useGetCollectionsQuery, useGetSessionsQuery } from "@/services/chat";
import { appPath } from "@/lib/app-path";
import TopBar from "@/app/TopBar";

export default function Layout({ params, children }: { params: Promise<{ collectionId: string }>, children: React.ReactNode }) {
    const allCollections = useAppSelector(state => state.chat.collections ?? []);
    const allAgents = useAppSelector(state => state.chat.agents ?? []);
    const allSessions = useAppSelector(state => state.chat.sessions ?? []);
    const router = useRouter();
    const routeParams = useParams<{ collectionId: string; sessionId?: string }>();

    const { isLoading: collectionsLoading } = useGetCollectionsQuery();
    const { isLoading: agentsLoading } = useGetAgentsQuery();
    useGetSessionsQuery();

    const { collectionId } = use(params)

    // Extract current session ID from the matched route params
    const currentSessionId = useMemo(() => {
        return routeParams.sessionId && routeParams.sessionId !== 'new' ? routeParams.sessionId : null;
    }, [routeParams.sessionId]);

    const thisCollection = allCollections.find(c => c.id === collectionId);
    const thisAgent = allAgents.find(a => a.id === collectionId);
    const theseSessions = useMemo(() => {
        // Show all sessions since API doesn't include collection_ids in response
        return allSessions;
    }, [allSessions]);

    const [showSidebar, setShowSidebar] = useState(false);


    if (collectionsLoading || agentsLoading) {
        return <Box sx={{ p: 3 }}>Loading chat...</Box>;
    }

    if (!thisCollection && !thisAgent) {
        return <div>Collection or agent not found.</div>;
    }

    return (
        <Box>
            <TopBar
                title={thisCollection?.name ?? thisAgent?.name}
                leftAction={
                    <IconButton size='large' edge="start" onClick={() => setShowSidebar(true)} sx={{ color: 'inherit' }}>
                        <MenuIcon />
                    </IconButton>
                }
                rightAction={
                    <IconButton size='large' onClick={() => router.replace(appPath(thisAgent ? '/agents' : '/chat'))} sx={{ color: 'inherit' }}>
                        <FirstPage />
                    </IconButton>
                }
            />
            <Box sx={{ flexDirection: 'row', }}>
                <Drawer
                    anchor="left"
                    open={showSidebar}
                    onClose={() => setShowSidebar(false)}

                >
                    <Box sx={{ width: 250 }} role="presentation" onClick={() => setShowSidebar(false)} >
                        <List>
                            <ListItem key={'new'} disablePadding>
                                <ListItemButton
                                    onClick={() => router.replace(appPath(`/chat/${collectionId}/new`))}
                                    selected={currentSessionId === 'new'}
                                >
                                    <ListItemText primary="New Chat" />
                                </ListItemButton>
                            </ListItem>
                            {theseSessions.map(s => (
                                <ListItem key={s.id} disablePadding>
                                    <ListItemButton
                                        onClick={() => router.replace(appPath(`/chat/${collectionId}/${s.id}`))}
                                        selected={currentSessionId === s.id}
                                    >
                                        <ListItemText primary={s.title} />
                                    </ListItemButton>
                                </ListItem>
                            ))}
                        </List>
                    </Box>
                </Drawer>
                {children}
            </Box>
        </Box>
    );
}
