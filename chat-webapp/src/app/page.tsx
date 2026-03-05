'use client'
import { useEffect } from "react";
import styles from "./page.module.css";
import { useRouter } from "next/navigation";

export default function Page() {
  const router = useRouter();
  useEffect(() => {
    router.replace('/chat');
  }, [router])

  return (
    <div className={styles.page}>

    </div>
  );
}
