import privacyDocument from '../../../docs/PRIVACY.md?raw';

export function GET() {
	return new Response(privacyDocument, {
		headers: { 'Content-Type': 'text/markdown; charset=utf-8' },
	});
}
