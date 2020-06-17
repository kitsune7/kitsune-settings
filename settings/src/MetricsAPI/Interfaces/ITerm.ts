interface ITerm {
  constant_id: number
  expression_id: number
  id: number
  isCurrentStatus?: boolean
  metric_profile_id: number
  name: string
  type: string
  variable_id: number
  operator?: string
  lh_term?: number
  rh_term?: number
  value?: string
}

export default ITerm
