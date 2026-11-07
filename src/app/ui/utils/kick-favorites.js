const STORAGE_KEY = "streamkickfusion-kick-favorites";

export function getFavorites() {
	try {
		const values = JSON.parse( localStorage.getItem( STORAGE_KEY ) || "[]" );
		return Array.isArray( values )
			? values.filter( value => typeof value === "string" )
			: [];
	} catch ( error ) {
		return [];
	}
}

export function saveFavorites( values ) {
	const normalized = values.map( value => value.trim().toLowerCase() ).filter( Boolean );
	const unique = Array.from( new Set( normalized ) );
	localStorage.setItem( STORAGE_KEY, JSON.stringify( unique ) );
	return unique;
}
