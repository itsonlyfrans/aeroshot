import securityDocument from '../../../docs/SECURITY.md?raw';

export function GET() {
	return new Response(securityDocument, {
		headers: { 'Content-Type': 'text/markdown; charset=utf-8' },
	});
}
