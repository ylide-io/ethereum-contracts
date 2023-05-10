export type Snapshot = {
	initial: string;
};

export enum FacetCutAction {
	Add,
	Replace,
	Remove,
}

export type FacetCut = {
	facetAddress: string;
	action: FacetCutAction;
	functionSelectors: string[];
};
