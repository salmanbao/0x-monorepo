import { MAINNET_CURVE_CONTRACTS } from './constants';

// tslint:disable completed-docs
export function getCurveAddressesForPair(takerToken: string, makerToken: string): string[] {
    return Object.keys(MAINNET_CURVE_CONTRACTS).filter(a =>
        [makerToken, takerToken].every(t => MAINNET_CURVE_CONTRACTS[a].includes(t)),
    );
}
