// Typed model for the Schwab viewer. CSV columns arrive as strings; the parse
// layer adds `<field>_num` numeric mirrors (matching the original app.js
// convention) so downstream metric code never re-parses.

export type AssetType =
  | "EQUITY"
  | "OPTION"
  | "COLLECTIVE_INVESTMENT"
  | "ETF"
  | "CASH_EQUIVALENT"
  | string;

/** A row with its string columns plus `<col>_num` numeric mirrors. */
export type NumericRow<T extends string = string> = Record<T, string> &
  Record<`${string}_num`, number | null> & { [key: string]: unknown };

export interface Position {
  symbol: string;
  underlying: string;
  description: string;
  asset_type: AssetType;
  put_call?: string;
  option_expiration?: string;
  option_strike?: string;
  net_quantity_num: number | null;
  market_value_num: number | null;
  current_day_profit_loss_num: number | null;
  long_open_profit_loss_num: number | null;
  average_price_num: number | null;
  [key: string]: unknown;
}

export interface Quote {
  symbol: string;
  description?: string;
  last_price_num: number | null;
  mark_num: number | null;
  net_change_num: number | null;
  [key: string]: unknown;
}

export interface PriceRow {
  symbol: string;
  date: string;
  close_num: number | null;
  [key: string]: unknown;
}

export interface LegacyTx {
  trade_date: string;
  action: string;
  symbol: string;
  underlying: string;
  instrument_type: string;
  option_expiration?: string;
  option_strike?: string;
  option_type?: string;
  side: string;
  price_num: number | null;
  cash_flow_num: number | null;
  source_row?: string;
  [key: string]: unknown;
}

export interface OptionRisk {
  symbol: string;
  underlying: string;
  put_call: string;
  expiration: string;
  strike_num: number | null;
  short_quantity_num: number | null;
  long_quantity_num: number | null;
  net_contracts_num: number | null;
  days_to_expiration_num: number | null;
  delta_num: number | null;
  theta_num: number | null;
  iv_num: number | null;
  assignment_notional_num: number | null;
  delta_dollars_num: number | null;
  [key: string]: unknown;
}

export interface AccountRow {
  liquidation_value_num: number | null;
  cash_balance_num: number | null;
  buying_power_num: number | null;
  long_market_value_num: number | null;
  short_option_market_value_num: number | null;
  maintenance_requirement_num: number | null;
  [key: string]: unknown;
}

export type EventType = "dividend_ex" | "dividend_pay" | "earnings" | string;

export interface PortfolioEvent {
  symbol: string;
  event_type: EventType;
  event_date: string;
  detail: string;
  [key: string]: unknown;
}

export interface SourceStatus {
  source: string;
  status: string;
  rows_num: number | null;
  detail: string;
  [key: string]: unknown;
}

export interface SecFiling {
  symbol: string;
  cik: string;
  company_name: string;
  form: string;
  filing_date: string;
  report_date: string;
  primary_document: string;
  description: string;
  [key: string]: unknown;
}

export interface MacroEvent {
  event_type: string;
  event_date: string;
  source: string;
  detail: string;
  importance: string;
  [key: string]: unknown;
}

export interface CryptoPrice {
  asset: string;
  price_usd_num: number | null;
  market_cap_usd_num: number | null;
  change_24h_pct_num: number | null;
  source: string;
  detail: string;
  [key: string]: unknown;
}

export interface AnalystRating {
  symbol: string;
  period: string;
  strong_buy_num: number | null;
  buy_num: number | null;
  hold_num: number | null;
  sell_num: number | null;
  strong_sell_num: number | null;
  source: string;
  [key: string]: unknown;
}

export interface NewsHeadline {
  symbol: string;
  datetime: string;
  headline: string;
  source: string;
  url: string;
  [key: string]: unknown;
}

export interface PortfolioData {
  meta: { date: string; source: string };
  accounts: AccountRow[];
  positions: Position[];
  quotes: Quote[];
  prices: PriceRow[];
  legacyTransactions: LegacyTx[];
  optionRisk: OptionRisk[];
  events: PortfolioEvent[];
  sourceStatus: SourceStatus[];
  secFilings: SecFiling[];
  macroEvents: MacroEvent[];
  cryptoPrices: CryptoPrice[];
  analystRatings: AnalystRating[];
  newsHeadlines: NewsHeadline[];
}
