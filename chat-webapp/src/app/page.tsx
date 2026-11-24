'use client'
import { useEffect } from "react";
import styles from "./page.module.css";
import { useRouter } from "next/navigation";
import { appPath } from "@/lib/app-path";

export default function Page() {
  const router = useRouter();
  useEffect(() => {
    router.replace(appPath('/chat'));
  }, [router])

  return (
    <div className={styles.page}>

    </div>
  );
}
