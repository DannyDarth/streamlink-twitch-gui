import Controller from "@ember/controller";
import { set } from "@ember/object";

export default Controller.extend({
	clientId: "01M6MZ2P7HESZTGFVKQHJ6HKKH",
	redirectUri: "http://127.0.0.1:17843/callback",
	clientSecret: "",
	status: "Not connected",

	actions: {
		clearSecret() {
			set( this, "clientSecret", "" );
			set( this, "status", "Secret cleared from this form." );
		}
	}
});
