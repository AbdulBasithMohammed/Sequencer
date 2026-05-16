import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/me";
import { FriendsClient, type FriendsData } from "./friends-client";

export const metadata = {
  title: "Friends — Sequencr",
};

export default async function FriendsPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");

  const supabase = await createClient();
  const { data } = await supabase.rpc("get_friends_data");
  const friendsData: FriendsData = (data as FriendsData) ?? {
    friends: [],
    incoming: [],
    sent: [],
    ignored: [],
  };

  return <FriendsClient data={friendsData} />;
}
