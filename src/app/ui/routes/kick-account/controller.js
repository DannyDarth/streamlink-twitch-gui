import Controller from "@ember/controller";
import { set } from "@ember/object";

const crypto = require( "crypto" );
const http = require( "http" );

let sessionTokens = null;
let pendingServer = null;

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

export default Controller.extend({
	clientId: "01M6MZ2P7HESZTGFVKQHJ6HKKH",
	redirectUri: "http://127.0.0.1:17843/callback",
	clientSecret: "",
	status: "Not connected",
	busy: false,

	actions: {
		clearSecret() {
			set( this, "clientSecret", "" );
		},
		disconnect() {
			sessionTokens = null;
			closePendingServer();
			set( this, "clientSecret", "" );
			set( this, "status", "Disconnected. Session tokens cleared from memory." );
		},
		async signIn() {
			if ( this.busy ) { return; }
			const clientId = ( this.clientId || "" ).trim();
			const secret = this.clientSecret || "";
			if ( !clientId || !secret ) {
				set( this, "status", "Enter your Client ID and Client Secret locally before signing in." );
				return;
			}
			if ( this.redirectUri !== "http://127.0.0.1:17843/callback" ) {
				set( this, "status",
					"For this test build, use the registered redirect URI http://127.0.0.1:17843/callback." );
				return;
			}
			set( this, "busy", true );
			set( this, "status", "Preparing secure browser authorization..." );
			closePendingServer();

			const state = base64url( crypto.randomBytes( 32 ) );
			const verifier = base64url( crypto.randomBytes( 32 ) );
			const challenge = base64url( crypto.createHash( "sha256" ).update( verifier ).digest() );
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
				handled = true;
				clearTimeout( timeout );
				const receivedState = url.searchParams.get( "state" );
				const code = url.searchParams.get( "code" );
				const error = url.searchParams.get( "error" );
				if ( !receivedState || receivedState !== state || !code || error ) {
					response.writeHead( 400, { "Content-Type": "text/plain" } );
					response.end( "Kick authorization failed. Return to the app." );
					set( this, "status",
						error ? "Kick denied authorization." : "Invalid authorization callback or state." );
					set( this, "busy", false );
					closePendingServer();
					return;
				}
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
					sessionTokens = tokens;
					set( this, "status", sessionTokens.access_token
						? "Connected to Kick for this app session. Tokens are memory-only."
						: "No access token received." );
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
