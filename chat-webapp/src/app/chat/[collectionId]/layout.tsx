'use client';
import { useAppSelector } from "@/store";
import { AppBar, Box, Drawer, IconButton, List, ListItem, ListItemButton, ListItemText, Toolbar } from "@mui/material";
import MenuIcon from '@mui/icons-material/Menu';
import FirstPage from '@mui/icons-material/FirstPage';
import { use, useMemo, useState } from "react";
import { useRouter, usePathname } from "next/navigation";

export default function Layout({ params, children }: { params: Promise<{ collectionId: string }>, children: React.ReactNode }) {
    const allCollections = useAppSelector(state => state.chat.collections ?? []);
    const allSessions = useAppSelector(state => state.chat.sessions ?? []);
    const router = useRouter();
    const pathname = usePathname();

    const { collectionId } = use(params)

    // Extract current session ID from pathname
    const currentSessionId = useMemo(() => {
        const pathParts = pathname.split('/');
        // Path format: /chat/[collectionId]/[sessionId]
        if (pathParts.length >= 4 && pathParts[3] !== 'new') {
            return pathParts[3];
        }
        return null;
    }, [pathname]);

    const thisCollection = allCollections.find(c => c.id === collectionId);
    const theseSessions = useMemo(() => {
        // Show all sessions since API doesn't include collection_ids in response
        return allSessions;
    }, [allSessions]);

    const [showSidebar, setShowSidebar] = useState(false);


    if (!thisCollection) {
        return <div>Collection not found.</div>;
    }

    return (
        <Box>
            <AppBar >
                <Toolbar>
                    <IconButton size='large' edge="start" onClick={() => setShowSidebar(true)} >
                        <MenuIcon />
                    </IconButton>
                    <IconButton size='large' edge="end" onClick={() => router.replace('/chat')} >
                        <FirstPage />
                    </IconButton>
                </Toolbar>
            </AppBar>
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
                                    onClick={() => router.replace(`/chat/${collectionId}/new`)}
                                    selected={currentSessionId === 'new'}
                                >
                                    <ListItemText primary="New Chat" />
                                </ListItemButton>
                            </ListItem>
                            {theseSessions.map(s => (
                                <ListItem key={s.id} disablePadding>
                                    <ListItemButton
                                        onClick={() => router.replace(`/chat/${collectionId}/${s.id}`)}
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