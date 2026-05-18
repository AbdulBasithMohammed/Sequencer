// Twitter cards use the same image as Open Graph. Next.js requires
// each route-config field to be a literal export (not re-exported), so
// we duplicate the constants and just reuse the rendering component.

export { default } from "./opengraph-image";

export const runtime = "edge";
export const alt = "Sequencr — Play Sequence online with friends.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
