import { readFile } from "node:fs/promises";
import path from "node:path";
import { UPLOADS_DIR } from "@/lib/blob";

// Railway template: serves editor uploads saved by lib/blob.js. Public, like a Blob store, because
// emails and archive pages load them without a session. Only names putImage creates are served.
const NAME_PATTERN = /^images\/[a-z0-9-]{1,100}\.(png|jpg|gif|webp)$/;
const CONTENT_TYPES = { png: "image/png", jpg: "image/jpeg", gif: "image/gif", webp: "image/webp" };

export async function GET(_request, { params }) {
	const name = ((await params).path ?? []).join("/");
	const match = NAME_PATTERN.exec(name);
	if (!match) return new Response("Not found", { status: 404 });

	let bytes;
	try {
		bytes = await readFile(path.join(UPLOADS_DIR, name));
	} catch (error) {
		if (error.code === "ENOENT") return new Response("Not found", { status: 404 });
		throw error;
	}
	return new Response(bytes, {
		headers: {
			"Content-Type": CONTENT_TYPES[match[1]],
			"Content-Length": String(bytes.length),
			"Cache-Control": "public, max-age=31536000, immutable",
		},
	});
}
