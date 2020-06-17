import PersistenceManager from '../../PersistenceManager/PersistenceManager'
import ICoordinate from '../../DBTableInterfaces/ICoordinate'

describe('Test get person Quadrant data translator', () => {
  jest.mock('../PersistenceManager')
  it('sends empty array for bad coordinate', async () => {
    const mockGetMostRecentCoordinateForUser = jest.fn()
    mockGetMostRecentCoordinateForUser.mockReturnValue(null)
    const pm = new PersistenceManager()
    pm.getMostRecentCoordinateForUser = mockGetMostRecentCoordinateForUser
    const metricsFromMetricsApi = []
    const termsFromMetricsApi = []

    const result = await pm.getPersonQuadrantStats(
      1,
      metricsFromMetricsApi,
      termsFromMetricsApi
    )
    expect(result.xMetrics.length).toEqual(0)
    expect(result.yMetrics.length).toEqual(0)
  })

  it('translates valid coordinate calc data', async () => {
    const coordinate: ICoordinate = {
      x: null,
      y: null,
      owner_id: null,
      company_id: null,
      date: null,
      coordinate_calc_data: {
        '216': {
          metricId: 216,
          name: 'Total Opportunities',
          performance: 0,
          target: 2.8571428571428568,
          unit: ' ',
          earliestStartDate: '2019-05-22',
          metric_id: 216,
          axis: 'x',
          weight: 100,
          max_credit: 200,
          num_target_periods: null,
          rolling_workdays: 20
        },
        '217': {
          metricId: 217,
          name: 'Prospecting Emails',
          performances: [
            {
              performance: 0,
              target: 10,
              startDate: '2020-04-01',
              endDate: '2020-04-30'
            },
            {
              performance: 5,
              target: 10,
              startDate: '2020-05-01',
              endDate: '2020-05-31'
            }
          ],
          unit: ' ',
          earliestStartDate: '2019-05-22',
          metric_id: 217,
          axis: 'y',
          weight: 100,
          max_credit: 200,
          num_target_periods: null,
          rolling_workdays: 30
        }
      }
    }
    const metricsFromMetricsApi = []
    const termsFromMetricsApi = []
    const mockGetMostRecentCoordinateForUser = jest.fn()
    mockGetMostRecentCoordinateForUser.mockReturnValue(coordinate)
    const pm = new PersistenceManager()
    pm.getMostRecentCoordinateForUser = mockGetMostRecentCoordinateForUser
    const result = await pm.getPersonQuadrantStats(
      1,
      metricsFromMetricsApi,
      termsFromMetricsApi
    )

    expect(result.xMetrics.length).toEqual(1)
    expect(result.yMetrics.length).toEqual(2)
  })
})
