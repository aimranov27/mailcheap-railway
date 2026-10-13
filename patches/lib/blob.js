import "server-only";
import { randomBytes } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { getAppUrl } from "@/lib/config";

// Railway template: editor uploads are saved on the service volume instead of Vercel Blob, and
// app/uploads/[...path]/route.js serves them. Sent emails point at these URLs forever, so a file
// is never overwritten: each one gets a random suffix, like Blob's addRandomSuffix.
export const UPLOADS_DIR = path.resolve(process.env.UPLOADS_DIR || "/data/uploads");

// Same signature as upstream. The content type isn't stored: the serving route derives it from the extension.
export async function putImage(pathname, bytes) {
	const extension = path.extname(pathname);
	const name = `${pathname.slice(0, -extension.length)}-${randomBytes(8).toString("hex")}${extension}`;
	const file = path.join(UPLOADS_DIR, name);
	if (!file.startsWith(UPLOADS_DIR + path.sep)) throw new Error("Invalid upload path");
	await mkdir(path.dirname(file), { recursive: true });
	await writeFile(file, bytes, { flag: "wx" });
	return `${getAppUrl()}/uploads/${name}`;
}
