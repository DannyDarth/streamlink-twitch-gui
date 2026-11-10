import Controller from "@ember/controller";
import { set } from "@ember/object";

const crypto = require( "crypto" );
const http = require( "http" );
const fs = require( "fs" );
const path = require( "path" );
const os = require( "os" );
const { spawn } = require( "child_process" );

let pendingServer = null;
let sessionGeneration = 0;
const storePath = path.join( process.env.LOCALAPPDATA || os.homedir(),
	"StreamKickFusion", "kick-session.dat" );


function closePendingServer() {
	if ( pendingServer ) {
		pendingServer.close();
		pendingServer = null;
	}
}

function base64url( bytes ) {
	return bytes.toString( "base64" )
		.replaceAll( "+", "-" ).replaceAll( "/", "_" ).replace( /=+$/g, "" );
}


function protectWithWindows( mode, input ) {
	if ( process.platform !== "win32" ) {
		return Promise.reject( new Error( "Saved login requires Windows" ) );
	}
	const script = [
		"$ErrorActionPreference = 'Stop'",
		"Add-Type -AssemblyName System.Security",
		"$raw = [Console]::In.ReadToEnd()",
		`if ('${mode}' -eq 'protect') {`,
		"  $bytes = [Text.Encoding]::UTF8.GetBytes($raw)",
		"  $output = [Security.Cryptography.ProtectedData]::Protect(",
		"    $bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)",
		"  [Console]::Out.Write([Convert]::ToBase64String($output))",
		"} else {",
		"  $bytes = [Convert]::FromBase64String($raw)",
		"  $output = [Security.Cryptography.ProtectedData]::Unprotect(",
		"    $bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)",
		"  [Console]::Out.Write([Text.Encoding]::UTF8.GetString($output))",
		"}"
	].join( "\n" );
	return new Promise( ( resolve, reject ) => {
		const encodedScript = Buffer.from( script, "utf16le" ).toString( "base64" );
		const child = spawn( "powershell.exe",
			[ "-NoProfile", "-NonInteractive", "-EncodedCommand", encodedScript ],
			{ windowsHide: true, stdio: [ "pipe", "pipe", "pipe" ] } );
		let output = "";
		let errorOutput = "";
		child.stdout.on( "data", chunk => { output += chunk.toString(); } );
		child.stderr.on( "data", chunk => {
			errorOutput += chunk.toString().slice( 0, 2000 );
		});
		child.on( "error", reject );
		child.on( "close", code => {
			if ( code === 0 ) { resolve( output ); } else {
				const details = errorOutput.split( "\n" )
					.find( line => line.includes( "Exception" ) || line.includes( "error" ) );
				const reason = details ? details.trim().slice( 0, 160 ) : `exit code ${code}`;
				reject( new Error( `Windows credential protection failed (${reason})` ) );
			}
		});
		child.stdin.end( input );
	});
}

async function saveSession( tokens, secret ) {
	if ( !tokens.refresh_token ) {
		throw new Error( "Kick did not provide a refresh token" );
	}
	const payload = JSON.stringify({ tokens, secret });
	const encrypted = await protectWithWindows( "protect", payload );
	await fs.promises.mkdir( path.dirname( storePath ), { recursive: true } );
	await fs.promises.writeFile( storePath, encrypted, { mode: 0o600 } );
}

async function loadSession() {
	const encrypted = await fs.promises.readFile( storePath, "utf8" );
	const payload = await protectWithWindows( "unprotect", encrypted );
	return JSON.parse( payload );
}

async function removeSavedSession() {
	try {
		await fs.promises.unlink( storePath );
	} catch ( error ) {
		if ( error.code !== "ENOENT" ) { throw error; }
	}
}

async function fetchAccountName( token ) {
	const response = await fetch( "https://api.kick.com/public/v1/users", {
		headers: { Authorization: `Bearer ${token}` }
	});
	if ( !response.ok ) { throw new Error( `HTTP ${response.status}` ); }
	const profile = await response.json();
	const data = profile && profile.data;
	const user = Array.isArray( data ) ? data[0] : data;
	const name = user && ( user.name || user.username || user.slug );
	if ( !name ) { throw new Error( "No account name in Kick response" ); }
	return name;
}

export default Controller.extend({
	init() {
		this._super( ...arguments );
		this.restoreSavedLogin();
	},
	async restoreSavedLogin() {
		const generation = sessionGeneration;
		try {
			const saved = await loadSession();
			if ( generation !== sessionGeneration ) { return; }
			set( this, "status", "Restoring saved Kick login..." );
			const body = new URLSearchParams({
				grant_type: "refresh_token",
				client_id: this.clientId,
				client_secret: saved.secret,
				refresh_token: saved.tokens.refresh_token
			});
			const result = await fetch( "https://id.kick.com/oauth/token", {
				method: "POST",
				headers: { "Content-Type": "application/x-www-form-urlencoded" },
				body: body.toString()
			});
			if ( !result.ok ) { throw new Error( `HTTP ${result.status}` ); }
			const tokens = await result.json();
			if ( !tokens.access_token ) { throw new Error( "No access token" ); }
			if ( generation !== sessionGeneration ) { return; }
			await saveSession( tokens, saved.secret );
			if ( generation !== sessionGeneration ) {
				await removeSavedSession();
				return;
			}
			const name = await fetchAccountName( tokens.access_token );
			if ( generation !== sessionGeneration ) { return; }
			set( this, "accountName", name );
			set( this, "status", "Connected to Kick (saved login restored)." );
		} catch ( error ) {
			if ( generation !== sessionGeneration ) { return; }
			if ( error.code === "ENOENT" ) { return; }
			set( this, "status", `Saved login could not be restored: ${error.message}` );
		}
	},
	clientId: "01M6MZ2P7HESZTGFVKQHJ6HKKH",
	redirectUri: "http://127.0.0.1:17843/callback",
	clientSecret: "",
	status: "Not connected",
	accountName: null,
	busy: false,

	actions: {
		clearSecret() {
			set( this, "clientSecret", "" );
		},
		async disconnect() {
			sessionGeneration++;
			set( this, "accountName", null );
			closePendingServer();
			set( this, "clientSecret", "" );
			try {
				await removeSavedSession();
				set( this, "status", "Disconnected. Saved Kick login removed." );
			} catch ( error ) {
				set( this, "status", `Could not remove saved login: ${error.message}` );
			}
		},
		async signIn() {
			if ( this.busy ) { return; }
			const clientId = ( this.clientId || "" ).trim();
			const secret = this.clientSecret || "";
			if ( !clientId || !secret ) {
				set( this, "status", "Enter Client ID and Client Secret before signing in." );
				return;
			}
			if ( this.redirectUri !== "http://127.0.0.1:17843/callback" ) {
				set( this, "status",
					"For this test build, use the registered redirect URI http://127.0.0.1:17843/callback." );
				return;
			}
			sessionGeneration++;
			const generation = sessionGeneration;
			set( this, "busy", true );
			set( this, "accountName", null );
			set( this, "status", "Preparing secure browser authorization..." );
			closePendingServer();

			const state = base64url( crypto.randomBytes( 32 ) );
			const verifier = base64url( crypto.randomBytes( 32 ) );
			const hash = crypto.createHash( "sha256" ).update( verifier ).digest();
			const challenge = base64url( hash );
			const redirectUri = this.redirectUri;
			let handled = false;
			let timeout;

			const server = http.createServer( async ( request, response ) => {
				const url = new URL( request.url, redirectUri );
				if ( url.pathname !== "/callback" ) {
					response.writeHead( 404 );
					response.end( "Not found" );
					return;
				}
				if ( handled ) {
					response.writeHead( 409 );
					response.end( "Callback already processed" );
					return;
				}
				// Ignore unsolicited requests without ending the legitimate OAuth attempt.
				// A bad callback must not consume the one-time authorization response.
				const receivedState = url.searchParams.get( "state" );
				const code = url.searchParams.get( "code" );
				const error = url.searchParams.get( "error" );
				const validState = receivedState && receivedState.length === state.length
					&& crypto.timingSafeEqual(
						Buffer.from( receivedState ), Buffer.from( state )
					);
				if ( request.method !== "GET" || !validState ) {
					response.writeHead( 400, { "Content-Type": "text/plain" } );
					response.end( "Invalid authorization callback." );
					return;
				}
				if ( error || !code ) {
					handled = true;
					clearTimeout( timeout );
					response.writeHead( 400, { "Content-Type": "text/plain" } );
					response.end( "Kick authorization failed. Return to the app." );
					set( this, "status", error
						? "Kick denied authorization." : "Missing authorization code." );
					set( this, "busy", false );
					closePendingServer();
					return;
				}
				handled = true;
				clearTimeout( timeout );
				response.writeHead( 200, { "Content-Type": "text/plain" } );
				response.end( "Kick authorization received. You may return to StreamKickFusion." );
				set( this, "status", "Exchanging authorization code..." );
				closePendingServer();
				try {
					const body = new URLSearchParams({
						grant_type: "authorization_code",
						client_id: clientId,
						client_secret: secret,
						redirect_uri: redirectUri,
						code_verifier: verifier,
						code
					});
					const result = await fetch( "https://id.kick.com/oauth/token", {
						method: "POST",
						headers: { "Content-Type": "application/x-www-form-urlencoded" },
						body: body.toString()
					});
					if ( !result.ok ) {
						throw new Error( `Token exchange failed (HTTP ${result.status})` );
					}
					const tokens = await result.json();
					if ( !tokens.access_token ) {
						throw new Error( "Kick returned no access token" );
					}
					if ( generation !== sessionGeneration ) { return; }
					set( this, "status", "Connected. Loading Kick account information..." );
					try {
						const name = await fetchAccountName( tokens.access_token );
						if ( generation !== sessionGeneration ) { return; }
						set( this, "accountName", name );
						set( this, "status", "Connected. Saving protected Kick login..." );
						await saveSession( tokens, secret );
						if ( generation !== sessionGeneration ) {
							await removeSavedSession();
							return;
						}
						set( this, "status", "Connected to Kick. Login saved for next launch." );
					} catch ( profileError ) {
						set( this, "status",
							`Connected, but profile or saving failed: ${profileError.message}` );
					}
				} catch ( exchangeError ) {
					set( this, "status", exchangeError.message );
				} finally {
					set( this, "clientSecret", "" );
					set( this, "busy", false );
				}
			});
			pendingServer = server;
			server.once( "error", error => {
				clearTimeout( timeout );
				set( this, "status", `Could not start local callback: ${error.message}` );
				set( this, "busy", false );
				closePendingServer();
			});
			server.listen( 17843, "127.0.0.1", () => {
				timeout = setTimeout( () => {
					set( this, "status", "Sign-in timed out. Please try again." );
					set( this, "busy", false );
					closePendingServer();
				}, 120000 );
				const params = new URLSearchParams({
					response_type: "code",
					client_id: clientId,
					redirect: "127.0.0.1",
					redirect_uri: redirectUri,
					scope: "user:read",
					state,
					code_challenge: challenge,
					code_challenge_method: "S256"
				});
				set( this, "status", "Complete authorization in your browser, then return here." );
				require( "nw.gui" ).Shell.openExternal( `https://id.kick.com/oauth/authorize?${params}` );
			});
		}
	}
});
